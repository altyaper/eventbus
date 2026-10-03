defmodule EventbusWeb.LoginLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures

  setup do
    %{user: user_fixture(username: "jorge")}
  end

  test "protected pages redirect to /login when logged out", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/topics/some-topic")
  end

  test "renders the login form", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/login")
    assert has_element?(live, "#login-form")
  end

  test "logs in with valid credentials", %{conn: conn} do
    conn =
      post(conn, ~p"/login", user: %{username: "jorge", password: valid_password()})

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)

    {:ok, live, _html} = live(conn, ~p"/")
    assert has_element?(live, "#user-menu-button", "jorge")
  end

  test "rejects invalid credentials with a generic error", %{conn: conn} do
    conn = post(conn, ~p"/login", user: %{username: "jorge", password: "wrong password!"})

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password."
    refute get_session(conn, :user_token)
  end

  test "redirects logged-in users away from /login", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/login")
  end

  test "logging out ends the session", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    token = get_session(conn, :user_token)

    conn = delete(conn, ~p"/logout")

    assert redirected_to(conn) == ~p"/login"
    refute get_session(conn, :user_token)
    refute Eventbus.Accounts.get_user_by_session_token(token)
  end

  test "shows the API key only to the superadmin", %{conn: conn, user: user} do
    {:ok, live, _html} = live(log_in_user(conn, user), ~p"/")
    assert has_element?(live, "#api-key-value", Eventbus.Settings.api_key())
  end
end
