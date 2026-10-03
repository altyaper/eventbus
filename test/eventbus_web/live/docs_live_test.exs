defmodule EventbusWeb.DocsLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures

  test "is public and highlights Docs in the top menu", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/docs")

    assert has_element?(live, "#nav-docs[aria-current=page]")
    refute has_element?(live, "#nav-apps")

    for section <- ~w(overview setup publish react javascript rules) do
      assert has_element?(live, "##{section}")
      assert has_element?(live, ~s(#docs-toc a[href="##{section}"]))
    end
  end

  test "logged-in users see both menu entries", %{conn: conn} do
    {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/docs")

    assert has_element?(live, "#nav-apps")
    assert has_element?(live, "#nav-docs[aria-current=page]")
  end

  test "the Docs link is in the menu on other pages", %{conn: conn} do
    {:ok, live, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/apps")

    assert has_element?(live, ~s(#nav-docs[href="/docs"]))
    refute has_element?(live, "#nav-docs[aria-current]")
  end

  test "snippets use the address the browser is on", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/docs")

    assert has_element?(
             live,
             "#snippet-curl",
             "http://www.example.com/api/topics/myapp.deploys/events"
           )

    assert has_element?(live, "#snippet-react", "ws://www.example.com/socket")
    assert has_element?(live, "#snippet-server", ~s(url: "http://www.example.com"))
    assert has_element?(live, "#snippet-install", "npm install @altyaper/eventbus-react")
  end
end
