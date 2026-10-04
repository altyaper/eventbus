defmodule EventbusWeb.AppsLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures

  alias Eventbus.Applications
  import Eventbus.AccountsFixtures

  test "/ redirects to My Apps", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/")) == ~p"/apps"
  end

  test "the global settings page is gone", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    assert get(conn, "/settings").status == 404
  end

  describe "as a confirmed user" do
    setup :register_and_log_in_user

    test "lists apps with their topic counts, linking to each app", %{conn: conn} do
      topic_fixture(name: "chat.lobby")
      app_fixture(slug: "empty")

      {:ok, live, _html} = live(conn, ~p"/apps")

      assert has_element?(live, "#nav-apps[aria-current=page]")
      assert has_element?(live, "#app-chat-topics", "1 topic")
      assert has_element?(live, "#app-empty-topics", "0 topics")
      assert has_element?(live, ~s(#app-chat[href="/apps/chat/topics"]))
      refute has_element?(live, "#settings-link")
    end

    test "creating an app shows its secret once", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/apps")
      assert has_element?(live, "#apps-empty")

      live |> form("#app-form", app: %{slug: "changologs"}) |> render_submit()

      app = Applications.get_app_by_slug("changologs")
      assert has_element?(live, "#app-changologs")
      assert has_element?(live, "#credentials-client-id", app.client_id)
      assert has_element?(live, "#credentials-secret", "ebs_")
      assert has_element?(live, ~s(#open-created[href="/apps/changologs/topics"]))

      live |> element("#dismiss-created") |> render_click()
      refute has_element?(live, "#created")
    end

    test "shows validation errors for a bad slug", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/apps")

      live |> form("#app-form", app: %{slug: "Bad.Slug"}) |> render_submit()

      assert has_element?(live, "#app-form", "must be lowercase")
    end
  end

  describe "ownership" do
    setup :register_and_log_in_user

    test "only lists the user's own apps", %{conn: conn} do
      app_fixture(slug: "mine")
      app_fixture(slug: "theirs", owner: user_fixture())

      {:ok, live, _html} = live(conn, ~p"/apps")

      assert has_element?(live, "#app-mine")
      refute has_element?(live, "#app-theirs")
      assert has_element?(live, "#apps-count", "1 app")
    end

    test "a new app belongs to its creator", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/apps")
      live |> form("#app-form", app: %{slug: "changologs"}) |> render_submit()

      assert Applications.get_app_by_slug("changologs").owner_id == user.id
    end
  end

  describe "when unconfirmed" do
    setup :register_and_log_in_unconfirmed_user

    test "can't create apps", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/apps")

      assert has_element?(live, "#app-form-locked")
      refute has_element?(live, "#app-form")

      render_hook(live, "create_app", %{"app" => %{"slug" => "sneaky"}})
      refute Applications.get_app_by_slug("sneaky")
    end
  end
end
