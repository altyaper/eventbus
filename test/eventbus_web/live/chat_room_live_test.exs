defmodule EventbusWeb.ChatRoomLiveTest do
  use EventbusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Broadcast, Messages, Presence, Rooms, Users}
  alias Eventbus.Accounts.User

  setup do
    app = app_fixture(slug: "acme")
    ann = caller_fixture(app, external_id: "ann", display_name: "Ann")
    %{app: app, ann: ann, room: room_fixture(app, %{name: "eng"}, [ann.user])}
  end

  test "an unknown room goes back to the chat section", %{conn: conn, app: app} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    other_room = room_fixture(app_fixture())

    for id <- ["nope", other_room.id] do
      assert {:error, {:live_redirect, %{to: "/apps/acme/chat"}}} =
               live(conn, ~p"/apps/#{app.slug}/chat/rooms/#{id}")
    end
  end

  describe "as the superadmin" do
    setup :register_and_log_in_user

    test "shows members and messages, newest first", %{conn: conn, ann: ann, room: room} do
      message_fixture(ann, room, %{"text" => "older"})
      newer = message_fixture(ann, room, %{"text" => "newer"})
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")

      assert has_element?(live, "#room-title", "eng")
      assert has_element?(live, "#member-ann", "Ann")
      assert has_element?(live, "#messages > li:nth-child(2)#message-#{newer.id}")
    end

    test "new messages and members appear live", %{conn: conn, app: app, ann: ann, room: room} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")

      {:ok, message, events} = Messages.send_message(ann, room, %{"text" => "live one"})
      Broadcast.dispatch(app, events)
      assert has_element?(live, "#message-#{message.id}", "live one")

      {:ok, _, events} = Rooms.add_member(app, room, "bo")
      Broadcast.dispatch(app, events)
      assert has_element?(live, "#member-bo")
      assert has_element?(live, "#members-count", "2")
    end

    test "shows who's online", %{conn: conn, room: room} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")
      assert has_element?(live, "#online-empty")

      topic = Broadcast.room_topic("acme", room.id)
      Phoenix.PubSub.subscribe(Eventbus.PubSub, topic)

      {:ok, _} =
        Presence.track(self(), topic, "ann", %{display_name: "Ann", avatar_url: nil, online_at: 0})

      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}

      assert has_element?(live, "#online-ann", "Ann")
    end

    test "adds and removes members", %{conn: conn, app: app, room: room} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")

      live |> form("#member-form", member: %{user_id: "cy", role: "moderator"}) |> render_submit()
      assert has_element?(live, "#member-cy", "mod")
      assert Rooms.get_member(room, Users.get_user(app, "cy")).role == "moderator"

      live |> element("#member-cy-remove") |> render_click()
      refute has_element?(live, "#member-cy")
      refute Rooms.member?(room, Users.get_user(app, "cy"))
    end

    test "shows an error for a bad user id", %{conn: conn, room: room} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")
      live |> form("#member-form", member: %{user_id: "has space"}) |> render_submit()
      assert has_element?(live, "#member-form", "must be letters")
    end

    test "loads older messages", %{conn: conn, ann: ann, room: room} do
      [first | _] = for n <- 1..51, do: message_fixture(ann, room, %{"text" => "m#{n}"})
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")

      refute has_element?(live, "#message-#{first.id}")
      live |> element("#load-older") |> render_click()
      assert has_element?(live, "#message-#{first.id}")
      refute has_element?(live, "#load-older")
    end

    test "direct rooms can't be changed", %{conn: conn, app: app} do
      {:ok, direct, _} = Rooms.create_direct_room(app, "ann", "bo")
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{direct.id}")

      assert has_element?(live, "#room-title", "Direct message")
      refute has_element?(live, "#member-form")
      refute has_element?(live, "#member-ann-remove")
    end
  end

  describe "as another user" do
    setup %{conn: conn} do
      member =
        Eventbus.Repo.insert!(%User{
          username: "member",
          hashed_password: Bcrypt.hash_pwd_salt("whatever password"),
          role: "member"
        })

      %{conn: log_in_user(conn, member)}
    end

    test "sees the room but can't manage members", %{conn: conn, app: app, room: room} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/rooms/#{room.id}")

      assert has_element?(live, "#member-ann")
      refute has_element?(live, "#member-form")
      refute has_element?(live, "#member-ann-remove")

      render_hook(live, "remove_member", %{"user-id" => "ann"})
      render_hook(live, "add_member", %{"member" => %{"user_id" => "cy", "role" => "member"}})
      assert Rooms.member?(room, Users.get_user(app, "ann"))
      assert Users.get_user(app, "cy") == nil
    end
  end
end
