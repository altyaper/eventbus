defmodule EventbusWeb.SessionController do
  use EventbusWeb, :controller

  alias Eventbus.Accounts
  alias EventbusWeb.UserAuth

  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    if user = Accounts.get_user_by_username_and_password(username, password) do
      UserAuth.log_in_user(conn, user)
    else
      # Same message for unknown usernames and wrong passwords, so the form
      # can't be used to discover which usernames exist.
      conn
      |> put_flash(:error, "Invalid username or password.")
      |> put_flash(:username, String.slice(username, 0, 32))
      |> redirect(to: ~p"/login")
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
