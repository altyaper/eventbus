defmodule EventbusWeb.PageController do
  use EventbusWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
