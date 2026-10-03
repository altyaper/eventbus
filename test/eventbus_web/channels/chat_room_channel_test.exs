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
end
