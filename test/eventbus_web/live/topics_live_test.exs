defmodule EventbusWeb.TopicsLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.TopicsFixtures

  setup :register_and_log_in_user

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

  test "groups topics under their app", %{conn: conn} do
    topic_fixture(name: "chat.lobby")
    topic_fixture(name: "standalone")

    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(live, "#app-chat", "chat.lobby")
    assert has_element?(live, "#ungrouped-topics", "standalone")
  end

  test "a created topic shows up in its app group", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    live
    |> form("#topic-form", topic: %{name: "chat.random"})
    |> render_submit()

    assert has_element?(live, "#app-chat", "chat.random")
  end

  test "the quick-start curl uses the address the browser is on", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")

    assert has_element?(
             live,
             "#curl-example",
             "http://www.example.com/api/topics/my.topic/events"
           )
  end

  test "deletes an app group and its topics", %{conn: conn} do
    for name <- ~w(chat.lobby chat.random deploys.prod), do: topic_fixture(name: name)

    {:ok, live, _html} = live(conn, ~p"/")
    refute has_element?(live, "#ungrouped-topics-delete")

    live |> element("#app-chat-confirm-delete") |> render_click()

    refute has_element?(live, "#app-chat")
    assert has_element?(live, "#app-deploys", "deploys.prod")
    assert has_element?(live, "#topics-count", "1 topic")
  end
end
