defmodule EventbusWeb.SignupLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures
  import Swoosh.TestAssertions

  alias Eventbus.{Accounts, Repo}
  alias Eventbus.Accounts.User

  defp signup_params(overrides \\ %{}) do
    Map.merge(
      %{
        email: "new@example.com",
        password: valid_password(),
        password_confirmation: valid_password(),
        terms: "true"
      },
      overrides
    )
  end

  test "needs setup first", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/setup"}}} = live(conn, ~p"/signup")
  end

  describe "once set up" do
    setup do
      %{admin: user_fixture(role: "superadmin")}
    end

    test "links to the legal pages and to login", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup")

      assert has_element?(live, ~s(#signup-form a[href="/terms"]))
      assert has_element?(live, ~s(#signup-form a[href="/privacy"]))
      assert has_element?(live, ~s(#login-link[href="/login"]))
    end

    test "login links to signup", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/login")
      assert has_element?(live, ~s(#signup-link[href="/signup"]))
    end

    test "validates as you type", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup")

      live
      |> form("#signup-form", user: %{email: "nope", password: "short"})
      |> render_change()

      assert has_element?(live, "#signup-form", "must have the @ sign")
      assert has_element?(live, "#signup-form", "at least 12")
    end

    test "requires accepting the terms", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup")

      live |> form("#signup-form", user: signup_params(%{terms: "false"})) |> render_submit()

      assert has_element?(live, "#signup-form", "must be accepted")
      refute Repo.get_by(User, email: "new@example.com")
    end

    test "creates the account, emails a link and logs in", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/signup")

      form = form(live, "#signup-form", user: signup_params())
      render_submit(form)

      user = Repo.get_by!(User, email: "new@example.com")
      refute user.confirmed_at
      assert_email_sent(to: [{"", "new@example.com"}], subject: "Confirm your eventbus email")

      conn = follow_trigger_action(form, conn)
      assert redirected_to(conn) == ~p"/apps"

      {:ok, apps, _html} = live(recycle(conn), ~p"/apps")
      assert has_element?(apps, "#confirm-banner", "new@example.com")
      assert has_element?(apps, "[id^=app-sandbox-]")
      assert has_element?(apps, "#app-form-locked")
    end

    test "logged-in users are sent to My Apps", %{conn: conn, admin: admin} do
      assert {:error, {:redirect, %{to: "/apps"}}} =
               conn |> log_in_user(admin) |> live(~p"/signup")
    end
  end

  test "Accounts.any_users?/0 stays false until signup or setup" do
    refute Accounts.any_users?()
  end
end
