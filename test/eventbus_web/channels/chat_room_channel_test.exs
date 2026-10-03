defmodule EventbusWeb.ChatRoomChannelTest do
  use EventbusWeb.ChannelCase

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Broadcast, Messages, Rooms}
  alias Eventbus.Origins
  alias EventbusWeb.{ChatRoomChannel, UserSocket}

  setup do
    app = app_fixture(slug: "acme")
    ann = caller_fixture(app, external_id: "ann", display_name: "Ann")
    bo = caller_fixture(app, external_id: "bo", display_name: "Bo")
    room = room_fixture(app, %{name: "eng"}, [ann.user, bo.user])
    %{app: app, ann: ann, bo: bo, room: room}
  end

  defp chat_socket(caller, origin \\ nil) do
    socket(UserSocket, "chat_socket:#{caller.user.id}", %{chat_caller: caller, origin: origin})
  end

  defp join_room(caller, room, params \\ %{}) do
    caller
    |> chat_socket()
    |> subscribe_and_join(ChatRoomChannel, Broadcast.room_topic(caller.app.slug, room.id), params)
  end

  describe "join" do
    test "a member gets the room, members and newest messages", %{ann: ann, room: room} do
      message_fixture(ann, room, %{"text" => "first"})

      assert {:ok, reply, _socket} = join_room(ann, room)
      assert reply.room.id == room.id
      assert reply.members |> Enum.map(& &1.user.id) |> Enum.sort() == ["ann", "bo"]
      assert [%{text: "first", sender: %{id: "ann"}}] = reply.messages
      assert %{has_more: false, gap_truncated: false} = reply
    end

    test "after returns only the missed messages", %{ann: ann, room: room} do
      seen = message_fixture(ann, room, %{"text" => "seen"})
      message_fixture(ann, room, %{"text" => "missed"})

      assert {:ok, reply, _socket} = join_room(ann, room, %{"after" => seen.id})
      assert [%{text: "missed"}] = reply.messages
      assert reply.gap_truncated == false
    end

    test "a gap longer than a page comes back as the newest page, flagged", %{
      ann: ann,
      room: room
    } do
      seen = message_fixture(ann, room)
      for n <- 1..(Messages.max_limit() + 1), do: message_fixture(ann, room, %{"text" => "m#{n}"})

      assert {:ok, reply, _socket} = join_room(ann, room, %{"after" => seen.id})
      assert reply.gap_truncated
      assert reply.has_more
      assert List.last(reply.messages).text == "m#{Messages.max_limit() + 1}"
    end

    test "non-members, unknown rooms and other apps get not_found", %{app: app, room: room} do
      outsider = caller_fixture(app)
      assert {:error, %{reason: "not_found"}} = join_room(outsider, room)
      assert {:error, %{reason: "not_found"}} = join_room(outsider, %{room | id: -1})

      other = app_fixture()
      other_caller = caller_fixture(other)

      # Their own slug with our room id, and our slug with their token.
      assert {:error, %{reason: "not_found"}} = join_room(other_caller, room)

      assert {:error, %{reason: "not_found"}} =
               other_caller
               |> chat_socket()
               |> subscribe_and_join(ChatRoomChannel, "chat:acme:#{room.id}")
    end

    test "anonymous sockets can't join", %{room: room} do
      assert {:error, %{reason: "unauthorized"}} =
               UserSocket
               |> socket(nil, %{origin: nil})
               |> subscribe_and_join(ChatRoomChannel, "chat:acme:#{room.id}")
    end

    test "joining a public room makes you a member and tells the room", %{app: app, ann: ann} do
      public = room_fixture(app, %{type: "public"}, [ann.user])
      {:ok, _, _} = join_room(ann, public)

      newcomer = caller_fixture(app, external_id: "cy")
      {:ok, _reply, _socket} = join_room(newcomer, public)

      assert Rooms.member?(public, newcomer.user)
      assert_push "chat.member.joined", %{member: %{user: %{id: "cy"}}}
    end
  end

  describe "origins" do
    setup %{app: app} do
      on_exit(fn -> :persistent_term.erase({Origins, :patterns}) end)
      {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://acme.com"})
      :ok
    end

    test "the app's origin may join, others may not", %{ann: ann, room: room} do
      topic = "chat:acme:#{room.id}"

      assert {:ok, _, _} =
               ann
               |> chat_socket(URI.parse("https://acme.com"))
               |> subscribe_and_join(ChatRoomChannel, topic)

      assert {:error, %{reason: "origin not allowed"}} =
               ann
               |> chat_socket(URI.parse("https://evil.example"))
               |> subscribe_and_join(ChatRoomChannel, topic)
    end
  end

  describe "message:send" do
    setup %{ann: ann, bo: bo, room: room} do
      {:ok, _, ann_socket} = join_room(ann, room)
      {:ok, _, _bo_socket} = join_room(bo, room)
      %{socket: ann_socket}
    end

    test "stores, replies and broadcasts to the room", %{socket: socket} do
      ref = push(socket, "message:send", %{"text" => "hi", "client_ref" => "c1"})

      assert_reply ref, :ok, %{
        message: %{id: id, text: "hi", client_ref: "c1", sender: %{id: "ann"}}
      }

      # Both joined sockets live in this test process, so it arrives twice.
      assert_push "chat.message.created", %{message: %{id: ^id}}
      assert_push "chat.message.created", %{message: %{id: ^id}}
    end

    test "a retried client_ref replies with the same message and doesn't rebroadcast", %{
      socket: socket
    } do
      ref = push(socket, "message:send", %{"text" => "hi", "client_ref" => "c1"})
      assert_reply ref, :ok, %{message: %{id: id}}
      assert_push "chat.message.created", _
      assert_push "chat.message.created", _

      ref = push(socket, "message:send", %{"text" => "hi", "client_ref" => "c1"})
      assert_reply ref, :ok, %{message: %{id: ^id}}
      refute_push "chat.message.created", _
    end

    test "the sender comes from the token, not the payload", %{socket: socket, bo: bo} do
      ref =
        push(socket, "message:send", %{
          "text" => "hi",
          "sender_id" => bo.user.id,
          "sender" => "bo"
        })

      assert_reply ref, :ok, %{message: %{sender: %{id: "ann"}}}
    end

    test "invalid messages reply with errors", %{socket: socket} do
      ref = push(socket, "message:send", %{"text" => ""})
      assert_reply ref, :error, %{reason: "invalid", errors: %{text: ["can't be blank"]}}
    end

    test "sending is rate limited", %{socket: socket} do
      for n <- 1..10 do
        ref = push(socket, "message:send", %{"text" => "m#{n}"})
        assert_reply ref, :ok, _
      end

      ref = push(socket, "message:send", %{"text" => "one too many"})
      assert_reply ref, :error, %{reason: "rate_limited"}
    end

    test "unknown events reply invalid", %{socket: socket} do
      ref = push(socket, "message:explode", %{})
      assert_reply ref, :error, %{reason: "invalid"}
    end
  end

  test "history pages back", %{ann: ann, room: room} do
    ids = for n <- 1..3, do: message_fixture(ann, room, %{"text" => "m#{n}"}).id
    {:ok, _, socket} = join_room(ann, room)

    ref = push(socket, "history", %{"before" => List.last(ids), "limit" => 1})
    assert_reply ref, :ok, %{messages: [%{text: "m2"}], has_more: true}
  end

  test "a removed member is told and the channel closes", %{app: app, ann: ann, room: room} do
    {:ok, _, socket} = join_room(ann, room)
    Process.unlink(socket.channel_pid)
    monitor = Process.monitor(socket.channel_pid)

    {:ok, _member, events} = Rooms.remove_member(app, room, "ann")
    Broadcast.dispatch(app, events)

    assert_push "chat.member.left", %{member: %{user: %{id: "ann"}}}
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
  end

  test "other members leaving keep the channel open", %{app: app, ann: ann, room: room} do
    {:ok, _, socket} = join_room(ann, room)

    {:ok, _member, events} = Rooms.remove_member(app, room, "bo")
    Broadcast.dispatch(app, events)

    assert_push "chat.member.left", %{member: %{user: %{id: "bo"}}}
    ref = push(socket, "history", %{})
    assert_reply ref, :ok, _
  end

  test "a socket whose user lost membership can't send", %{app: app, ann: ann, room: room} do
    {:ok, _, socket} = join_room(ann, room)
    # Removed without the event reaching the channel.
    {:ok, _, _events} = Rooms.remove_member(app, room, "ann")

    ref = push(socket, "message:send", %{"text" => "hi"})
    assert_reply ref, :error, %{reason: "not_found"}
    assert Messages.list_messages(room).messages == []
  end

  describe "presence" do
    test "joining pushes the current state and tracks you", %{ann: ann, bo: bo, room: room} do
      {:ok, _, _} = join_room(ann, room)
      assert_push "presence_state", %{}
      assert_push "presence_diff", %{joins: %{"ann" => _}}

      {:ok, _, _} = join_room(bo, room)
      assert_push "presence_state", state
      assert Map.has_key?(state, "ann")
      assert_push "presence_diff", %{joins: %{"bo" => %{metas: [%{display_name: "Bo"}]}}}
    end

    test "two connections of one user are one key with two metas", %{ann: ann, room: room} do
      {:ok, _, _} = join_room(ann, room)
      {:ok, _, _} = join_room(ann, room)

      topic = Broadcast.room_topic("acme", room.id)
      assert_push "presence_diff", %{joins: %{"ann" => _}}
      assert_push "presence_diff", %{joins: %{"ann" => _}}
      assert %{"ann" => %{metas: [_, _]}} = Eventbus.Chat.Presence.list(topic)
    end

    test "closing a connection removes it", %{ann: ann, room: room} do
      {:ok, _, socket} = join_room(ann, room)
      assert_push "presence_diff", %{joins: %{"ann" => _}}

      Process.unlink(socket.channel_pid)
      ref = leave(socket)
      assert_reply ref, :ok

      assert_receive %Phoenix.Socket.Broadcast{
        event: "presence_diff",
        payload: %{leaves: %{"ann" => _}}
      }
    end
  end

  describe "typing" do
    # subscribe_and_join also subscribes this process to the room topic, so
    # it sees broadcasts the way another member's channel would.
    setup %{ann: ann, room: room} do
      {:ok, _, ann_socket} = join_room(ann, room)
      %{socket: ann_socket}
    end

    test "starts, throttles and stops", %{socket: socket} do
      push(socket, "typing", %{"typing" => true})
      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", %{user_id: "ann"}}
      refute_receive {:chat_event, "chat.typing.started", _}, 20

      push(socket, "typing", %{"typing" => false})
      assert_receive {:chat_event, "chat.typing.stopped", %{user_id: "ann"}}
      # The typist's own channel doesn't get its typing back.
      refute_push "chat.typing.started", _
    end

    # Not async, so changing the throttle can't affect other tests.
    test "is re-broadcast while it goes on", %{socket: socket} do
      throttle = Application.fetch_env!(:eventbus, :chat_typing_throttle_ms)
      Application.put_env(:eventbus, :chat_typing_throttle_ms, 0)
      on_exit(fn -> Application.put_env(:eventbus, :chat_typing_throttle_ms, throttle) end)

      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", _}
      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", _}
    end

    test "expires without a refresh", %{socket: socket} do
      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", _}
      assert_receive {:chat_event, "chat.typing.stopped", %{user_id: "ann"}}, 500
    end

    test "sending a message stops it", %{socket: socket} do
      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", _}

      ref = push(socket, "message:send", %{"text" => "done"})
      assert_reply ref, :ok, _
      assert_receive {:chat_event, "chat.typing.stopped", _}, 50
    end

    test "leaving stops it", %{socket: socket} do
      push(socket, "typing", %{"typing" => true})
      assert_receive {:chat_event, "chat.typing.started", _}

      Process.unlink(socket.channel_pid)
      leave(socket)
      assert_receive {:chat_event, "chat.typing.stopped", _}, 50
    end
  end

  describe "read" do
    test "marks read, replies and tells the user's channel", %{ann: ann, bo: bo, room: room} do
      message = message_fixture(bo, room)
      {:ok, reply, socket} = join_room(ann, room)
      assert reply.read_state == %{last_read_message_id: nil}

      Phoenix.PubSub.subscribe(Eventbus.PubSub, Broadcast.user_topic("acme", "ann"))
      ref = push(socket, "read", %{"message_id" => message.id})
      id = message.id
      assert_reply ref, :ok, %{last_read_message_id: ^id}
      assert_receive {:chat_event, "read_state.updated", %{room_id: _, unread_count: 0}}

      assert {:ok, %{read_state: %{last_read_message_id: ^id}}, _} = join_room(ann, room)
    end

    test "rejects other rooms' messages and bad ids", %{app: app, ann: ann, room: room} do
      other = room_fixture(app, %{}, [ann.user])
      message = message_fixture(ann, other)
      {:ok, _, socket} = join_room(ann, room)

      ref = push(socket, "read", %{"message_id" => message.id})
      assert_reply ref, :error, %{reason: "not_found"}
      ref = push(socket, "read", %{"message_id" => "x"})
      assert_reply ref, :error, %{reason: "invalid"}
    end
  end

  describe "edit, delete, replies and reactions" do
    setup %{ann: ann, bo: bo, room: room} do
      message = message_fixture(ann, room, %{"text" => "original"})
      {:ok, _, ann_socket} = join_room(ann, room)
      {:ok, _, bo_socket} = join_room(bo, room)
      %{message: message, ann_socket: ann_socket, bo_socket: bo_socket}
    end

    test "the author edits; others are forbidden", %{message: message} = ctx do
      id = message.id
      ref = push(ctx.ann_socket, "message:edit", %{"id" => id, "text" => "fixed"})
      assert_reply ref, :ok, %{message: %{id: ^id, text: "fixed", edited_at: %DateTime{}}}
      assert_push "chat.message.updated", %{message: %{id: ^id, text: "fixed"}}

      ref = push(ctx.bo_socket, "message:edit", %{"id" => id, "text" => "hijack"})
      assert_reply ref, :error, %{reason: "forbidden"}
    end

    test "the author deletes; others are forbidden", %{message: message} = ctx do
      id = message.id
      ref = push(ctx.bo_socket, "message:delete", %{"id" => id})
      assert_reply ref, :error, %{reason: "forbidden"}

      ref = push(ctx.ann_socket, "message:delete", %{"id" => id})
      assert_reply ref, :ok, %{message: %{id: ^id, text: "", deleted_at: %DateTime{}}}
      assert_push "chat.message.deleted", %{message: %{id: ^id}}
    end

    test "replies carry a preview", %{message: message} = ctx do
      ref =
        push(ctx.bo_socket, "message:send", %{"text" => "re", "reply_to_id" => message.id})

      assert_reply ref, :ok, %{message: %{reply_to: %{text: "original", sender: %{id: "ann"}}}}
    end

    test "reactions are added, deduplicated and removed", %{message: message} = ctx do
      id = message.id
      ref = push(ctx.bo_socket, "reaction:add", %{"message_id" => id, "emoji" => "👍"})
      assert_reply ref, :ok
      assert_push "chat.reaction.added", %{message_id: ^id, user_id: "bo", emoji: "👍"}
      assert_push "chat.reaction.added", _

      ref = push(ctx.bo_socket, "reaction:add", %{"message_id" => id, "emoji" => "👍"})
      assert_reply ref, :ok
      refute_push "chat.reaction.added", _

      ref = push(ctx.bo_socket, "reaction:remove", %{"message_id" => id, "emoji" => "👍"})
      assert_reply ref, :ok
      assert_push "chat.reaction.removed", %{user_id: "bo"}

      ref = push(ctx.bo_socket, "reaction:add", %{"message_id" => id, "emoji" => "nope"})
      assert_reply ref, :error, %{reason: "invalid"}
    end
  end
end
