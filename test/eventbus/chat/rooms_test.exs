defmodule Eventbus.Chat.RoomsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Caller, Rooms, Users}

  setup do
    app = app_fixture()

    %{
      app: app,
      ann: chat_user_fixture(app, external_id: "ann"),
      bo: chat_user_fixture(app, external_id: "bo")
    }
  end

  describe "create_room/3" do
    test "adds the members and the creator as moderator, with events", %{app: app} do
      {:ok, room, events} =
        Rooms.create_room(app, %{name: " engineering ", type: "group"},
          members: ["ann", "new-user"],
          created_by: "bo"
        )

      assert room.name == "engineering"
      members = Rooms.list_members(room)

      assert Enum.map(members, &{&1.user.external_id, &1.role}) ==
               [{"bo", "moderator"}, {"ann", "member"}, {"new-user", "member"}]

      # A member nobody has minted a token for yet starts with their id as name.
      assert Users.get_user(app, "new-user").display_name == "new-user"

      assert Enum.count(events, &match?({:user, _, "room.member.added", _}, &1)) == 3
      assert Enum.count(events, &match?({:room, _, "chat.member.joined", _}, &1)) == 3
    end

    test "rejects direct rooms and bad names", %{app: app} do
      assert {:error, changeset} = Rooms.create_room(app, %{name: "x", type: "direct"})
      assert "is invalid" in errors_on(changeset).type
      assert {:error, changeset} = Rooms.create_room(app, %{name: "", type: "group"})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "rejects an invalid member id and creates nothing", %{app: app} do
      assert {:error, changeset} =
               Rooms.create_room(app, %{name: "x", type: "group"}, members: ["has space"])

      assert errors_on(changeset).external_id != []
      assert Rooms.list_app_rooms(app) == []
    end
  end

  describe "create_direct_room/3" do
    test "creates one room per pair, in either order", %{app: app} do
      {:ok, room, events} = Rooms.create_direct_room(app, "ann", "bo")
      assert room.type == "direct"
      assert length(events) == 4

      assert {:ok, ^room, []} = Rooms.create_direct_room(app, "bo", "ann")
      assert length(Rooms.list_members(room)) == 2
    end

    test "needs two different users", %{app: app} do
      assert {:error, :same_user} = Rooms.create_direct_room(app, "ann", "ann")
    end

    test "can't gain or lose members", %{app: app} do
      {:ok, room, _} = Rooms.create_direct_room(app, "ann", "bo")
      assert {:error, :direct_room} = Rooms.add_member(app, room, "cy")
      assert {:error, :direct_room} = Rooms.remove_member(app, room, "ann")
    end
  end

  describe "members" do
    test "add_member adds once and changes roles", %{app: app, ann: ann} do
      room = room_fixture(app)

      {:ok, member, [_, _]} = Rooms.add_member(app, room, "ann")
      assert member.role == "member"
      assert {:ok, _member, []} = Rooms.add_member(app, room, "ann")
      assert {:ok, %{role: "moderator"}, []} = Rooms.add_member(app, room, "ann", "moderator")
      assert Rooms.get_member(room, ann).role == "moderator"

      assert {:error, changeset} = Rooms.add_member(app, room, "bo", "owner")
      assert "is invalid" in errors_on(changeset).role
    end

    test "remove_member removes and reports events", %{app: app, ann: ann} do
      room = room_fixture(app, %{}, [ann])

      {:ok, _member, events} = Rooms.remove_member(app, room, "ann")
      refute Rooms.member?(room, ann)
      assert [{:room, _, "chat.member.left", _}, {:user, ^ann, "room.member.removed", _}] = events

      assert {:error, :not_found} = Rooms.remove_member(app, room, "ann")
      assert {:error, :not_found} = Rooms.remove_member(app, room, "nobody")
    end
  end

  describe "open_room/2" do
    test "members may open their rooms; others get :not_found", %{app: app, ann: ann, bo: bo} do
      room = room_fixture(app, %{}, [ann])

      assert {:ok, ^room, []} = Rooms.open_room(Caller.new(app, ann), room.id)
      assert {:error, :not_found} = Rooms.open_room(Caller.new(app, bo), room.id)
      assert {:error, :not_found} = Rooms.open_room(Caller.new(app, ann), "nope")
    end

    test "opening a public room joins it", %{app: app, bo: bo} do
      room = room_fixture(app, %{type: "public"})

      assert {:ok, _room, [_, _]} =
               Rooms.open_room(Caller.new(app, bo), Integer.to_string(room.id))

      assert Rooms.member?(room, bo)
      assert {:ok, _room, []} = Rooms.open_room(Caller.new(app, bo), room.id)
    end

    test "another app's room is :not_found, public or not", %{app: app} do
      other = app_fixture()
      room = room_fixture(other, %{type: "public"})

      assert {:error, :not_found} = Rooms.open_room(caller_fixture(app), room.id)
      assert Rooms.get_app_room(app, room.id) == nil
    end
  end

  test "list_user_rooms/1 lists only the user's rooms, latest activity first", %{
    app: app,
    ann: ann,
    bo: bo
  } do
    quiet = room_fixture(app, %{name: "quiet"}, [ann])
    busy = room_fixture(app, %{name: "busy"}, [ann, bo])
    _not_mine = room_fixture(app, %{name: "other"}, [bo])
    {:ok, direct, _} = Rooms.create_direct_room(app, "ann", "bo")

    message_fixture(Caller.new(app, bo), busy, %{"text" => "latest"})

    rooms = Rooms.list_user_rooms(Caller.new(app, ann))
    assert Enum.map(rooms, & &1.room.id) == [busy.id, direct.id, quiet.id]

    [busy_entry, direct_entry, _] = rooms
    assert busy_entry.last_message.text == "latest"
    assert busy_entry.unread_count == 1
    assert busy_entry.members == []
    assert direct_entry.last_message == nil
    assert direct_entry.members |> Enum.map(& &1.user.external_id) |> Enum.sort() == ["ann", "bo"]
  end

  test "list_app_rooms/1 counts members", %{app: app, ann: ann, bo: bo} do
    room_fixture(app, %{name: "two"}, [ann, bo])
    assert [%{name: "two", members_count: 2}] = Rooms.list_app_rooms(app)
  end
end
