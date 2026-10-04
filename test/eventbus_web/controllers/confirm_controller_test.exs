defmodule EventbusWeb.ConfirmControllerTest do
  use EventbusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Eventbus.AccountsFixtures
  import Swoosh.TestAssertions

  alias Eventbus.{Accounts, Repo}
  alias Eventbus.Accounts.User

  setup do
    user = user_fixture(confirmed: false)
    {:ok, _} = Accounts.deliver_user_confirmation_instructions(user, capture_token_url())
    assert_received {:token, token}
    assert_email_sent()
    %{user: user, token: token}
  end

  describe "GET /confirm/:token" do
    test "confirms while logged out and sends to login", %{conn: conn, user: user, token: token} do
      conn = get(conn, ~p"/confirm/#{token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Email confirmed"
      assert Repo.get!(User, user.id).confirmed_at
    end

    test "confirms while logged in and lifts the limits", %{conn: conn, user: user, token: token} do
      conn = conn |> log_in_user(user) |> get(~p"/confirm/#{token}")
      assert redirected_to(conn) == ~p"/apps"

      {:ok, live, _html} = live(recycle(conn), ~p"/apps")
      refute has_element?(live, "#confirm-banner")
      assert has_element?(live, "#app-form")
    end

    test "a bad link says so without confirming", %{conn: conn, user: user} do
      conn = get(conn, ~p"/confirm/nonsense")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
      refute Repo.get!(User, user.id).confirmed_at
    end
  end

  describe "POST /confirm/resend" do
    test "respects the one-minute cooldown", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> post(~p"/confirm/resend")

      assert redirected_to(conn) == ~p"/apps"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Wait a minute"
      refute_email_sent()
    end

    test "sends a new link after the cooldown", %{conn: conn, user: user} do
      Repo.update_all(Accounts.UserToken,
        set: [inserted_at: DateTime.add(DateTime.utc_now(), -2, :minute)]
      )

      conn = conn |> log_in_user(user) |> post(~p"/confirm/resend")

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "sent a new confirmation link"
      assert_email_sent(subject: "Confirm your eventbus email")
    end

    test "requires login", %{conn: conn} do
      assert redirected_to(post(conn, ~p"/confirm/resend")) == ~p"/login"
    end
  end
end
