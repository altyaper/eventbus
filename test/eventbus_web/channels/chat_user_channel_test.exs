defmodule EventbusWeb.ChatUserChannelTest do
  use EventbusWeb.ChannelCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Broadcast, Rooms}
  alias EventbusWeb.{ChatUserChannel, UserSocket}

  setup do
    app = app_fixture(slug: "acme")
    %{app: app, ann: caller_fixture(app, external_id: "ann")}
  end

  defp join_user(caller, topic) do
    UserSocket
    |> socket("chat_socket:#{caller.user.id}", %{chat_caller: caller, origin: nil})
    |> subscribe_and_join(ChatUserChannel, topic)
  end

  test "joining your own channel replies with your rooms", %{app: app, ann: ann} do
    room = room_fixture(app, %{name: "eng"}, [ann.user])
    message_fixture(ann, room, %{"text" => "hey"})

    assert {:ok, reply, _socket} = join_user(ann, "chat_user:acme:ann")
    assert reply.user.id == "ann"
    assert [%{id: id, name: "eng", last_message: %{text: "hey"}, unread_count: 0}] = reply.rooms
    assert id == room.id
  end

  test "you can't join someone else's channel or another app's", %{app: app, ann: ann} do
    chat_user_fixture(app, external_id: "bo")
    assert {:error, %{reason: "forbidden"}} = join_user(ann, "chat_user:acme:bo")
    assert {:error, %{reason: "forbidden"}} = join_user(ann, "chat_user:other:ann")

    assert {:error, %{reason: "unauthorized"}} =
             UserSocket
             |> socket(nil, %{origin: nil})
             |> subscribe_and_join(ChatUserChannel, "chat_user:acme:ann")
  end

  test "messages in your rooms arrive as room.activity", %{app: app, ann: ann} do
    bo = caller_fixture(app, external_id: "bo")
    room = room_fixture(app, %{}, [ann.user, bo.user])
    {:ok, _, _socket} = join_user(ann, "chat_user:acme:ann")

    {:ok, _message, events} = Eventbus.Chat.Messages.send_message(bo, room, %{"text" => "ping"})
    Broadcast.dispatch(app, events)

    room_id = room.id

    assert_push "room.activity", %{
      room_id: ^room_id,
      message: %{text: "ping", sender: %{id: "bo"}}
    }
  end

  test "being added to and removed from rooms arrives here", %{app: app, ann: ann} do
    {:ok, _, _socket} = join_user(ann, "chat_user:acme:ann")
    room = room_fixture(app)

    {:ok, _, events} = Rooms.add_member(app, room, "ann")
    Broadcast.dispatch(app, events)
    assert_push "room.member.added", %{room: %{id: id}}
    assert id == room.id

    {:ok, _, events} = Rooms.remove_member(app, room, "ann")
    Broadcast.dispatch(app, events)
    assert_push "room.member.removed", %{room_id: ^id}
  end
end
