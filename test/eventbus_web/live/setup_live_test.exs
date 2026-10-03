defmodule EventbusWeb.SetupLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures

  alias Eventbus.Accounts

  defp setup_params(overrides \\ %{}) do
    Map.merge(
      %{
        username: "admin",
        password: valid_password(),
        password_confirmation: valid_password(),
        api_key: Eventbus.Settings.api_key()
      },
      overrides
    )
  end

  test "pages redirect to /setup while no user exists", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/setup"}}} = live(conn, ~p"/")
    assert {:error, {:redirect, %{to: "/setup"}}} = live(conn, ~p"/login")
  end

  test "rejects a wrong API key without creating a user", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/setup")

    live
    |> form("#setup-form", user: setup_params(%{api_key: "nope"}))
    |> render_submit()

    assert has_element?(live, "#setup-form", "doesn't match this server's API key")
    refute Accounts.any_users?()
  end

  test "creates the superadmin and submits the login form", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/setup")

    form = form(live, "#setup-form", user: setup_params())
    render_submit(form)

    assert Accounts.any_users?()

    conn = follow_trigger_action(form, conn)
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
  end

  test "is locked once a user exists", %{conn: conn} do
    user_fixture()
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/setup")
  end
end
