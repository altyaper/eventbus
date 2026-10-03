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

  test "an unknown topic redirects to the applications page", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/topics/test.nope")
  end

  test "renders a pushed PubSub event while listening", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/test.live-test-topic")

    live |> element("button", "Start listening") |> render_click()

    Events.publish("test.live-test-topic", %{"hello" => "world"})

    assert render(live) =~ "hello"
  end

  test "the Start/Stop toggle stops new events from rendering", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/test.toggle-test-topic")

    live |> element("button", "Start listening") |> render_click()
    live |> element("button", "Stop listening") |> render_click()

    Events.publish("test.toggle-test-topic", %{"should_not" => "appear"})

    refute render(live) =~ "should_not"
  end

  test "the test-publish form round-trips through Events.publish/2", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/test.publish-test-topic")

    live |> element("button", "Start listening") |> render_click()

    live
    |> form("form", test: %{payload: ~s({"from": "test form"})})
    |> render_submit()

    assert render(live) =~ "from"
  end
end
