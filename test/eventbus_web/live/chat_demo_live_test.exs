defmodule EventbusWeb.ChatDemoLiveTest do
  use EventbusWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Eventbus.ApplicationsFixtures

  alias Eventbus.Chat.{Messages, Rooms, Tokens, Users}
  alias Eventbus.Accounts.User

  setup do
    %{app: app_fixture(slug: "acme")}
  end

  describe "as the superadmin" do
    setup :register_and_log_in_user

    test "acting as a user mounts the SDK hook", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/demo")
      refute has_element?(live, "[phx-hook=ChatDemo]")

      live |> form("#act-form", act: %{user_id: "ann", display_name: "Ann"}) |> render_submit()

      user = Users.get_user(app, "ann")
      assert user.display_name == "Ann"
      assert has_element?(live, "#chat-demo-#{user.id}[phx-hook=ChatDemo]")

      live |> element("#stop-acting") |> render_click()
      assert has_element?(live, "#act-form")
    end

    test "the display name defaults to the user id; bad ids show an error", %{
      conn: conn,
      app: app
    } do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/demo")

      live |> form("#act-form", act: %{user_id: "has space"}) |> render_submit()
      assert has_element?(live, "#act-form", "must be letters")

      live |> form("#act-form", act: %{user_id: "bo"}) |> render_submit()
      assert Users.get_user(app, "bo").display_name == "bo"
    end

    test "hands the hook a token for the acting user", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/demo")
      render_hook(live, "token", %{})
      assert_reply live, %{error: "not acting"}

      live |> form("#act-form", act: %{user_id: "ann", display_name: "Ann"}) |> render_submit()
      user = Users.get_user(app, "ann")

      hook = element(live, "#chat-demo-#{user.id}")
      render_hook(hook, "token", %{})
      assert_reply live, %{token: token, app: "acme", user: %{id: "ann"}}
      assert {:ok, caller} = Tokens.verify(token)
      assert caller.user.id == user.id
    end

    test "seeds sample rooms, idempotently", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/acme/chat/demo")
      live |> form("#act-form", act: %{user_id: "ann", display_name: "Ann"}) |> render_submit()

      live |> element("#seed-rooms") |> render_click()
      live |> element("#seed-rooms") |> render_click()

      rooms = Rooms.list_app_rooms(app)
      assert rooms |> Enum.map(& &1.type) |> Enum.sort() == ~w(direct group public)

      ann = Users.get_user(app, "ann")
      for room <- rooms, do: assert(Rooms.member?(room, ann))
      assert [_, _] = Messages.list_messages(Enum.find(rooms, &(&1.type == "direct"))).messages
    end
  end

  test "other users are sent back to the chat section", %{conn: conn} do
    member =
      Eventbus.Repo.insert!(%User{
        username: "member",
        hashed_password: Bcrypt.hash_pwd_salt("whatever password"),
        role: "member"
      })

    assert {:error, {:live_redirect, %{to: "/apps/acme/chat"}}} =
             conn |> log_in_user(member) |> live(~p"/apps/acme/chat/demo")
  end
end
