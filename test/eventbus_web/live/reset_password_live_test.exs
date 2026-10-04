defmodule EventbusWeb.ResetPasswordLiveTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures
  import Swoosh.TestAssertions

  alias Eventbus.Accounts

  setup do
    %{user: user_fixture()}
  end

  test "login links to the reset page", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/login")
    assert has_element?(live, ~s(#forgot-password-link[href="/reset-password"]))
  end

  describe "requesting a link" do
    test "answers the same for unknown emails and sends nothing", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/reset-password")

      {:ok, login, _html} =
        live
        |> form("#reset-request-form", user: %{email: "nobody@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert has_element?(login, "#flash-info", "If that email has an account")
      refute_email_sent()
    end

    test "emails a link to an existing account", %{conn: conn, user: user} do
      {:ok, live, _html} = live(conn, ~p"/reset-password")

      live |> form("#reset-request-form", user: %{email: user.email}) |> render_submit()

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.text_body =~ "/reset-password/"
      end)
    end
  end

  describe "the reset link" do
    setup %{user: user} do
      :ok = Accounts.deliver_user_reset_password_instructions(user.email, capture_token_url())
      assert_received {:token, token}
      %{token: token}
    end

    test "an invalid link goes back to the request page", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/reset-password", flash: flash}}} =
               live(conn, ~p"/reset-password/nope")

      assert flash["error"] =~ "invalid or has expired"
    end

    test "validates the new password", %{conn: conn, token: token} do
      {:ok, live, _html} = live(conn, ~p"/reset-password/#{token}")

      live
      |> form("#reset-password-form", user: %{password: "short", password_confirmation: "x"})
      |> render_submit()

      assert has_element?(live, "#reset-password-form", "at least 12")
    end

    test "sets the password and logs out every session", %{conn: conn, user: user, token: token} do
      old_conn = log_in_user(build_conn(), user)
      old_token = get_session(old_conn, :user_token)

      {:ok, live, _html} = live(conn, ~p"/reset-password/#{token}")

      {:ok, login, _html} =
        live
        |> form("#reset-password-form",
          user: %{password: "a brand new password", password_confirmation: "a brand new password"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/login")

      assert has_element?(login, "#flash-info", "Password changed")
      refute Accounts.get_user_by_session_token(old_token)
      assert {:error, {:redirect, %{to: "/login"}}} = live(old_conn, ~p"/apps")

      conn =
        post(build_conn(), ~p"/login",
          user: %{email: user.email, password: "a brand new password"}
        )

      assert redirected_to(conn) == ~p"/apps"
    end
  end
end
