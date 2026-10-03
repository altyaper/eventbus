defmodule Eventbus.Chat.MessagesTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Messages, Room}
  alias Eventbus.Repo

  setup do
    app = app_fixture()
    caller = caller_fixture(app, external_id: "ann")
    %{app: app, caller: caller, room: room_fixture(app, %{}, [caller.user])}
  end

  describe "send_message/3" do
    test "stores the message, bumps the room and returns the event", %{caller: caller, room: room} do
      {:ok, message, [event | _activity]} =
        Messages.send_message(caller, room, %{"text" => "  hi  ", "metadata" => %{"k" => 1}})

      assert message.text == "hi"
      assert message.sender_id == caller.user.id
      assert {:room, ^room, "chat.message.created", %{room_id: room_id, message: payload}} = event
      assert room_id == room.id
      assert payload.sender.id == "ann"

      room = Repo.get!(Room, room.id)
      assert room.last_message_id == message.id
      assert room.last_message_at == message.inserted_at
    end

    test "tells every member about the activity", %{app: app, caller: caller, room: room} do
      {:ok, _member, _} = Eventbus.Chat.Rooms.add_member(app, room, "bo")

      {:ok, _message, [_created | activity]} =
        Messages.send_message(caller, room, %{"text" => String.duplicate("x", 300)})

      assert activity
             |> Enum.map(fn {:user, user, "room.activity", _} -> user.external_id end)
             |> Enum.sort() ==
               ["ann", "bo"]

      [{:user, _, _, %{message: preview}} | _] = activity
      assert String.length(preview.text) == 140
    end

    test "the same client_ref returns the stored message without events", %{
      caller: caller,
      room: room
    } do
      {:ok, first, [_ | _]} =
        Messages.send_message(caller, room, %{"text" => "hi", "client_ref" => "r1"})

      {:ok, again, []} =
        Messages.send_message(caller, room, %{"text" => "hi", "client_ref" => "r1"})

      assert again.id == first.id
      assert %{messages: [_]} = Messages.list_messages(room)
    end

    test "only members may send", %{app: app, room: room} do
      assert {:error, :not_found} =
               Messages.send_message(caller_fixture(app), room, %{"text" => "hi"})
    end

    test "validates text and metadata", %{caller: caller, room: room} do
      for {attrs, field} <- [
            {%{"text" => "   "}, :text},
            {%{"text" => String.duplicate("a", 4001)}, :text},
            {%{"text" => "hi", "metadata" => "nope"}, :metadata},
            {%{"text" => "hi", "metadata" => %{"big" => String.duplicate("a", 5000)}}, :metadata}
          ] do
        assert {:error, changeset} = Messages.send_message(caller, room, attrs)
        assert Map.has_key?(errors_on(changeset), field)
      end
    end

    test "ignores attempts to set the sender or room", %{app: app, caller: caller, room: room} do
      other = chat_user_fixture(app)

      {:ok, message, _} =
        Messages.send_message(caller, room, %{
          "text" => "hi",
          "sender_id" => other.id,
          "room_id" => -1
        })

      assert message.sender_id == caller.user.id
      assert message.room_id == room.id
    end
  end

  describe "list_messages/2" do
    setup %{caller: caller, room: room} do
      ids = for n <- 1..5, do: message_fixture(caller, room, %{"text" => "m#{n}"}).id
      %{ids: ids}
    end

    test "newest page, oldest first", %{room: room, ids: ids} do
      assert %{messages: messages, has_more: true} = Messages.list_messages(room, limit: 3)
      assert Enum.map(messages, & &1.id) == Enum.slice(ids, 2..4)
      assert hd(messages).sender.external_id == "ann"
    end

    test "before pages back", %{room: room, ids: ids} do
      assert %{messages: messages, has_more: false} =
               Messages.list_messages(room, before: Enum.at(ids, 2), limit: 3)

      assert Enum.map(messages, & &1.id) == Enum.slice(ids, 0..1)
    end

    test "after fills a gap", %{room: room, ids: ids} do
      assert %{messages: messages, has_more: true} =
               Messages.list_messages(room, after: Enum.at(ids, 0), limit: 2)

      assert Enum.map(messages, & &1.id) == Enum.slice(ids, 1..2)

      assert %{messages: [], has_more: false} =
               Messages.list_messages(room, after: List.last(ids))
    end

    test "limit is clamped", %{room: room} do
      assert %{messages: [_]} = Messages.list_messages(room, limit: 0)
      assert %{messages: messages} = Messages.list_messages(room, limit: 10_000)
      assert length(messages) == 5
    end

    test "doesn't mix rooms", %{app: app, caller: caller} do
      other = room_fixture(app, %{}, [caller.user])
      assert %{messages: [], has_more: false} = Messages.list_messages(other)
    end
  end
end
