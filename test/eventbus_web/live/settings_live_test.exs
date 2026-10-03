defmodule EventbusWeb.SettingsLiveTest do
  # Not async: adding origins refreshes the global pattern cache.
  use EventbusWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Eventbus.Accounts.User
  alias Eventbus.Origins

  setup :register_and_log_in_user

  setup do
    on_exit(fn -> :persistent_term.erase({Origins, :patterns}) end)
  end

  test "adds and removes an origin", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/settings")
    assert has_element?(live, "#origins-empty")

    live
    |> form("#origin-form", allowed_origin: %{origin: "https://changologs.com"})
    |> render_submit()

    [origin] = Origins.list_allowed_origins()
    assert has_element?(live, "#origins-#{origin.id}", "https://changologs.com")

    live |> element("#origins-#{origin.id}-remove") |> render_click()

    refute has_element?(live, "#origins-#{origin.id}")
    assert Origins.list_allowed_origins() == []
  end

  test "shows a validation error for an invalid origin", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/settings")

    live
    |> form("#origin-form", allowed_origin: %{origin: "not an origin"})
    |> render_submit()

    assert has_element?(live, "#origin-form", "must look like")
    assert Origins.list_allowed_origins() == []
  end

  test "lists env origins as locked", %{conn: conn} do
    Application.put_env(:eventbus, :env_origins, ["eventbus.example.dev"])
    on_exit(fn -> Application.delete_env(:eventbus, :env_origins) end)

    {:ok, live, _html} = live(conn, ~p"/settings")
    assert has_element?(live, "#env-origins", "eventbus.example.dev")
    refute has_element?(live, "#env-origins button")
  end

  test "the superadmin sees the link in the user menu", %{conn: conn} do
    {:ok, live, _html} = live(conn, ~p"/")
    assert has_element?(live, "#settings-link")
  end

  test "other users are sent back to the topics page", %{conn: conn} do
    member =
      Eventbus.Repo.insert!(%User{
        username: "member",
        hashed_password: Bcrypt.hash_pwd_salt("whatever password"),
        role: "member"
      })

    conn = log_in_user(conn, member)
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/settings")
  end
end
