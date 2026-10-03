defmodule EventbusWeb.TopicsLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.TopicsFixtures

  test "lists existing topics", %{conn: conn} do
    topic = topic_fixture()

    {:ok, _live, html} = live(conn, ~p"/")

    assert html =~ topic.name
  end

  test "creates a new topic", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    html =
      live
      |> form("#topic-form", topic: %{name: "a-new-topic"})
      |> render_submit()

    assert html =~ "a-new-topic"
  end
end
