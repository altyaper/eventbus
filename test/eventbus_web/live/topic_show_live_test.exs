defmodule EventbusWeb.TopicShowLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.TopicsFixtures

  setup :register_and_log_in_user

  alias Eventbus.Events

  setup do
    for name <- ~w(test.live-test-topic test.toggle-test-topic test.publish-test-topic),
        do: topic_fixture(name: name)

    :ok
  end

  test "an unknown topic redirects to its app's topics", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/apps/test/topics"}}} =
             live(conn, ~p"/apps/test/topics/test.nope")
  end

  test "another app's topic redirects to this app's topics", %{conn: conn} do
    topic_fixture(name: "other.lobby")

    assert {:error, {:live_redirect, %{to: "/apps/test/topics"}}} =
             live(conn, ~p"/apps/test/topics/other.lobby")
  end

  test "an unknown app redirects to My Apps", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/apps"}}} = live(conn, ~p"/apps/nope/topics/nope.x")
  end

  test "shows the topic inside its app", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/apps/test/topics/test.live-test-topic")

    assert has_element?(live, "#breadcrumb", "test.live-test-topic")
    assert has_element?(live, "#section-topics[aria-current=page]")
  end

  test "renders a pushed PubSub event while listening", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/apps/test/topics/test.live-test-topic")

    live |> element("button", "Start listening") |> render_click()

    Events.publish("test.live-test-topic", %{"hello" => "world"})

    assert render(live) =~ "hello"
  end

  test "the Start/Stop toggle stops new events from rendering", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/apps/test/topics/test.toggle-test-topic")

    live |> element("button", "Start listening") |> render_click()
    live |> element("button", "Stop listening") |> render_click()

    Events.publish("test.toggle-test-topic", %{"should_not" => "appear"})

    refute render(live) =~ "should_not"
  end

  test "the test-publish form round-trips through Events.publish/2", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/apps/test/topics/test.publish-test-topic")

    live |> element("button", "Start listening") |> render_click()

    live
    |> form("form", test: %{payload: ~s({"from": "test form"})})
    |> render_submit()

    assert render(live) =~ "from"
  end
end
