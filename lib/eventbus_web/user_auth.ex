defmodule EventbusWeb.UserAuth do
  @moduledoc """
  Session-based login for the web UI: a plug that loads `@current_scope`,
  helpers to log in and out, and `on_mount` hooks guarding LiveViews.
  """

  use EventbusWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Eventbus.Accounts
  alias Eventbus.Accounts.Scope

  @doc """
  Logs the user in: renews the session (against fixation), stores a fresh
  session token and redirects to the topics page.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, live_socket_id(token))
    |> redirect(to: ~p"/apps")
  end

  @doc """
  Logs the user out: deletes the session token, disconnects their open
  LiveViews and clears the session.
  """
  def log_out_user(conn) do
    if token = get_session(conn, :user_token) do
      Accounts.delete_user_session_token(token)
      EventbusWeb.Endpoint.broadcast(live_socket_id(token), "disconnect", %{})
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/login")
  end

  @doc """
  Disconnects the open LiveViews of the given (already deleted) session
  tokens, e.g. after a password reset ended every session.
  """
  def disconnect_sessions(tokens) do
    for token <- tokens do
      EventbusWeb.Endpoint.broadcast(live_socket_id(token), "disconnect", %{})
    end

    :ok
  end

  defp live_socket_id(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Plug that assigns `:current_scope` from the session token.
  """
  def fetch_current_scope(conn, _opts) do
    user = (token = get_session(conn, :user_token)) && Accounts.get_user_by_session_token(token)
    assign(conn, :current_scope, Scope.for_user(user))
  end

  @doc """
  LiveView hooks:

    * `:mount_current_scope` - only assigns it, for public pages.
    * `:require_setup` - redirects to `/setup` while no user exists.
    * `:require_authenticated` - redirects to `/login` unless logged in.
    * `:require_superadmin` - redirects to `/apps` unless the user is the
      superadmin. Use after `:require_authenticated`.
    * `:redirect_if_authenticated` - sends logged-in users to `/apps`.
    * `:redirect_if_set_up` - keeps `/setup` reachable only before the
      first user exists.

  Every hook assigns `:current_scope` first.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_setup, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.any_users?() do
      {:cont, socket}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}
    end
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Log in to continue.")
       |> Phoenix.LiveView.redirect(to: ~p"/login")}
    end
  end

  def on_mount(:require_superadmin, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Scope.superadmin?(socket.assigns.current_scope) do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Only the superadmin can open that page.")
       |> Phoenix.LiveView.redirect(to: ~p"/apps")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/apps")}
    else
      {:cont, socket}
    end
  end

  def on_mount(:redirect_if_set_up, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Accounts.any_users?() do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
    else
      {:cont, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      user = (token = session["user_token"]) && Accounts.get_user_by_session_token(token)
      Scope.for_user(user)
    end)
  end
end
