defmodule EventbusWeb.TopicShowLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Eventbus.Events

  test "renders a pushed PubSub event while listening", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/live-test-topic")

    live |> element("button", "Start listening") |> render_click()

    Events.publish("live-test-topic", %{"hello" => "world"})

    assert render(live) =~ "hello"
  end

  test "the Start/Stop toggle stops new events from rendering", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/toggle-test-topic")

    live |> element("button", "Start listening") |> render_click()
    live |> element("button", "Stop listening") |> render_click()

    Events.publish("toggle-test-topic", %{"should_not" => "appear"})

    refute render(live) =~ "should_not"
  end

  test "the test-publish form round-trips through Events.publish/2", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/topics/publish-test-topic")

    live |> element("button", "Start listening") |> render_click()

    live
    |> form("form", test: %{payload: ~s({"from": "test form"})})
    |> render_submit()

    assert render(live) =~ "from"
  end
end
