defmodule EventbusWeb.TopicsLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures

  alias Eventbus.{Applications, Topics}
  alias Eventbus.Accounts.User

  describe "as the superadmin" do
    setup :register_and_log_in_user

    test "lists applications with their topics", %{conn: conn} do
      topic_fixture(name: "chat.lobby")
      app_fixture(slug: "empty")

      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#app-chat", "chat.lobby")
      assert has_element?(live, "#app-empty", "No topics yet")
    end

    test "creating an app shows its secret once", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")
      assert has_element?(live, "#apps-empty")

      live |> form("#app-form", app: %{slug: "changologs"}) |> render_submit()

      [app] = Applications.list_apps_with_topics()
      assert has_element?(live, "#app-changologs")
      assert has_element?(live, "#credentials-client-id", app.client_id)
      assert has_element?(live, "#credentials-secret", "ebs_")

      live |> element("#dismiss-credentials") |> render_click()
      refute has_element?(live, "#credentials")

      # Reopening shows the client id but not the secret.
      live |> element("#app-changologs-credentials") |> render_click()
      assert has_element?(live, "#credentials-client-id", app.client_id)
      refute has_element?(live, "#credentials-secret")
    end

    test "regenerating replaces the secret", %{conn: conn} do
      app = app_fixture(slug: "chat")
      {:ok, live, _html} = live(conn, ~p"/")

      live |> element("#app-chat-credentials") |> render_click()
      live |> element("#regenerate-confirm-button") |> render_click()

      assert has_element?(live, "#credentials-secret", "ebs_")
      assert :error = Applications.authenticate(app.client_id, app.secret)
    end

    test "creates a topic under the chosen app", %{conn: conn} do
      app = app_fixture(slug: "chat")
      {:ok, live, _html} = live(conn, ~p"/")

      live
      |> form("#topic-form", topic: %{application_id: app.id, name: "lobby"})
      |> render_change()

      assert has_element?(live, "#topic-full-name", "chat.lobby")

      live
      |> form("#topic-form", topic: %{application_id: app.id, name: "lobby"})
      |> render_submit()

      assert has_element?(live, "#app-chat", "chat.lobby")
      assert Topics.get_topic_by_name("chat.lobby")
    end

    test "requires an app and a valid name for new topics", %{conn: conn} do
      app = app_fixture(slug: "chat")
      {:ok, live, _html} = live(conn, ~p"/")

      live |> form("#topic-form", topic: %{name: "lobby"}) |> render_submit()
      assert has_element?(live, "#topic-form", "choose an application")

      live
      |> form("#topic-form", topic: %{application_id: app.id, name: "Bad Name"})
      |> render_submit()

      assert has_element?(live, "#topic-form", "must be lowercase")
      assert Topics.list_topics() == []
    end

    test "deletes an app and its topics", %{conn: conn} do
      for name <- ~w(chat.lobby chat.random deploys.prod), do: topic_fixture(name: name)
      {:ok, live, _html} = live(conn, ~p"/")

      live |> element("#app-chat-confirm-delete") |> render_click()

      refute has_element?(live, "#app-chat")
      assert has_element?(live, "#app-deploys", "deploys.prod")
      assert has_element?(live, "#topics-count", "1 topic")
      refute Topics.get_topic_by_name("chat.lobby")
    end

    test "the quick-start curl uses the address the browser is on", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(
               live,
               "#curl-example",
               "http://www.example.com/api/topics/my-app.my-topic/events"
             )
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

    test "sees apps and topics without management controls", %{conn: conn} do
      topic_fixture(name: "chat.lobby")
      {:ok, live, _html} = live(conn, ~p"/")

      assert has_element?(live, "#app-chat", "chat.lobby")
      refute has_element?(live, "#app-form")
      refute has_element?(live, "#topic-form")
      refute has_element?(live, "#app-chat-credentials")
      refute has_element?(live, "#app-chat-confirm-delete")
    end

    test "can't trigger management events directly", %{conn: conn} do
      app = app_fixture(slug: "chat")
      {:ok, live, _html} = live(conn, ~p"/")

      render_hook(live, "delete_app", %{"id" => app.id})

      assert Applications.get_app!(app.id)
    end
  end
end
