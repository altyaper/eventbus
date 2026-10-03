defmodule EventbusWeb.HomeController do
  use EventbusWeb, :controller

  # My Apps is the home page; /apps itself requires login.
  def index(conn, _params), do: redirect(conn, to: ~p"/apps")
end
