defmodule EventbusWeb.AppLiveTest do
  # Not async: adding origins refreshes the global pattern cache.
  use EventbusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.{Applications, Origins, Topics}
  alias Eventbus.Chat.Rooms

  setup do
    on_exit(fn -> :persistent_term.erase({Origins, :patterns}) end)
    %{app: app_fixture(slug: "chat")}
  end

  test "an unknown app redirects to My Apps", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})
    assert {:error, {:live_redirect, %{to: "/apps"}}} = live(conn, ~p"/apps/nope/topics")
  end

  describe "as the owner" do
    setup :register_and_log_in_user

    test "/apps/:slug opens the topics section", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/apps/chat/topics"}}} = live(conn, ~p"/apps/chat")
    end

    test "sections switch by patching", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/topics")

      for section <- ~w(chat credentials origins settings topics) do
        live |> element("#section-#{section}") |> render_click()
        assert_patched(live, "/apps/chat/#{section}")
        assert has_element?(live, "#section-#{section}[aria-current=page]")
      end
    end

    test "lists and creates topics", %{conn: conn} do
      topic_fixture(name: "chat.lobby")
      topic_fixture(name: "other.thing")
      {:ok, live, _html} = live(conn, ~p"/apps/chat/topics")

      assert has_element?(live, "#topics", "chat.lobby")
      refute has_element?(live, "#topics", "other.thing")

      live |> form("#topic-form", topic: %{name: "random"}) |> render_submit()

      assert has_element?(live, "#topics", "chat.random")
      assert has_element?(live, "#topics-count", "2 topics")
      assert Topics.get_topic_by_name("chat.random")
    end

    test "groups topics by name segment and drills into a group", %{conn: conn} do
      for name <- ~w(chat.lobby chat.board.a chat.board.b), do: topic_fixture(name: name)
      {:ok, live, _html} = live(conn, ~p"/apps/chat/topics")

      assert has_element?(live, "#topic-group-board", "2 topics")
      assert has_element?(live, "#topics", "chat.lobby")
      refute has_element?(live, "#topics", "chat.board.a")

      live |> element("#topic-group-board a") |> render_click()
      assert_patched(live, "/apps/chat/topics?group=board")

      assert has_element?(live, "#topic-crumbs", "board")
      assert has_element?(live, "#topics", "chat.board.a")
      refute has_element?(live, "#topics", "chat.lobby")

      live |> form("#topic-form", topic: %{name: "c"}) |> render_submit()
      assert Topics.get_topic_by_name("chat.board.c")
      assert has_element?(live, "#topics-count", "3 topics")
    end

    test "lists and creates chat rooms", %{conn: conn, app: app} do
      room_fixture(app, %{name: "eng"})
      room_fixture(app_fixture(), %{name: "elsewhere"})
      {:ok, live, _html} = live(conn, ~p"/apps/chat/chat")

      assert has_element?(live, "#rooms", "eng")
      refute has_element?(live, "#rooms", "elsewhere")

      live |> form("#room-form", room: %{name: "random", type: "public"}) |> render_submit()

      assert has_element?(live, "#rooms", "random")
      assert has_element?(live, "#rooms-count", "2 rooms")
      assert [%{type: "public"}] = Enum.filter(Rooms.list_app_rooms(app), &(&1.name == "random"))
    end

    test "rejects a blank room name", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/chat")
      live |> form("#room-form", room: %{name: "", type: "group"}) |> render_submit()

      assert has_element?(live, "#room-form", "can't be blank")
      assert Rooms.list_app_rooms(app) == []
    end

    test "rejects invalid topic names", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/topics")

      live |> form("#topic-form", topic: %{name: "Bad Name"}) |> render_submit()

      assert has_element?(live, "#topic-form", "must be lowercase")
      assert Topics.list_topics() == []
    end

    test "credentials show the client id and regenerate the secret", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/credentials")

      assert has_element?(live, "#credentials-client-id", app.client_id)
      refute has_element?(live, "#credentials-secret")

      assert has_element?(
               live,
               "#curl-example",
               "http://www.example.com/api/topics/chat.my-topic/events"
             )

      live |> element("#regenerate-confirm-button") |> render_click()

      assert has_element?(live, "#credentials-secret", "ebs_")
      assert :error = Applications.authenticate(app.client_id, app.secret)
    end

    test "adds and removes an origin", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/origins")
      assert has_element?(live, "#origins-empty")

      live
      |> form("#origin-form", allowed_origin: %{origin: "https://chat.example"})
      |> render_submit()

      [origin] = Origins.list_allowed_origins(app)
      assert has_element?(live, "#origin-#{origin.id}", "https://chat.example")
      assert Origins.allowed_for_topic?(URI.parse("https://chat.example"), "chat.lobby")

      live |> element("#origin-#{origin.id}-remove") |> render_click()

      refute has_element?(live, "#origin-#{origin.id}")
      assert Origins.list_allowed_origins(app) == []
    end

    test "shows a validation error for an invalid origin", %{conn: conn, app: app} do
      {:ok, live, _html} = live(conn, ~p"/apps/chat/origins")

      live
      |> form("#origin-form", allowed_origin: %{origin: "not an origin"})
      |> render_submit()

      assert has_element?(live, "#origin-form", "must look like")
      assert Origins.list_allowed_origins(app) == []
    end

    test "lists env origins as always allowed", %{conn: conn} do
      Application.put_env(:eventbus, :env_origins, ["eventbus.example.dev"])
      on_exit(fn -> Application.delete_env(:eventbus, :env_origins) end)

      {:ok, live, _html} = live(conn, ~p"/apps/chat/origins")
      assert has_element?(live, "#env-origins", "eventbus.example.dev")
      refute has_element?(live, "#env-origins button")
    end

    test "deleting the app disconnects its chat sockets", %{conn: conn, app: app} do
      user = chat_user_fixture(app)
      EventbusWeb.Endpoint.subscribe("chat_socket:#{user.id}")
      {:ok, live, _html} = live(conn, ~p"/apps/chat/settings")

      live |> element("#delete-confirm-button") |> render_click()
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "toggles requiring topic tokens from settings", %{conn: conn, app: app} do
      on_exit(fn -> :persistent_term.erase({Eventbus.TopicTokens, :required_slugs}) end)
      {:ok, live, _html} = live(conn, ~p"/apps/chat/settings")
      assert has_element?(live, ~s(#toggle-topic-tokens[aria-checked="false"]))

      live |> element("#toggle-topic-tokens") |> render_click()
      assert has_element?(live, ~s(#toggle-topic-tokens[aria-checked="true"]))
      assert Applications.get_app!(app.id).require_topic_tokens
      assert Eventbus.TopicTokens.required?("chat")

      live |> element("#toggle-topic-tokens") |> render_click()
      refute Applications.get_app!(app.id).require_topic_tokens
      refute Eventbus.TopicTokens.required?("chat")
    end

    test "deletes the app from settings", %{conn: conn, app: app} do
      topic_fixture(name: "chat.lobby")
      {:ok, live, _html} = live(conn, ~p"/apps/chat/settings")

      live |> element("#delete-confirm-button") |> render_click()

      assert_redirect(live, ~p"/apps")
      refute Applications.get_app_by_slug("chat")
      refute Topics.get_topic_by_name("chat.lobby")
      assert_raise Ecto.NoResultsError, fn -> Applications.get_app!(app.id) end
    end
  end

  describe "as another user" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, Eventbus.AccountsFixtures.user_fixture())}
    end

    test "every section sends them back to My Apps", %{conn: conn} do
      for section <- ~w(topics chat credentials origins settings) do
        assert {:error, {:live_redirect, %{to: "/apps", flash: flash}}} =
                 live(conn, "/apps/chat/#{section}")

        assert flash["error"] =~ "There's no application chat"
      end
    end
  end

  describe "when the owner is unconfirmed" do
    setup %{conn: conn} do
      owner = Eventbus.AccountsFixtures.user_fixture(confirmed: false)
      app = app_fixture(slug: "sandbox-abc", owner: owner)
      %{conn: log_in_user(conn, owner), app: app}
    end

    test "topics are capped and the form says so", %{conn: conn, app: app} do
      for i <- 1..4, do: topic_fixture(app: app, name: "sandbox-abc.t#{i}")
      {:ok, live, _html} = live(conn, ~p"/apps/sandbox-abc/topics")

      assert has_element?(live, "#topic-usage", "4/5")

      live |> form("#topic-form", topic: %{name: "fifth"}) |> render_submit()
      assert has_element?(live, "#topic-usage", "5/5")

      live |> form("#topic-form", topic: %{name: "sixth"}) |> render_submit()
      assert has_element?(live, "#topic-form", "confirm your email")
      refute Topics.get_topic_by_name("sandbox-abc.sixth")
    end
  end
end
