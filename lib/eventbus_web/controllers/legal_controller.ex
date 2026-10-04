defmodule EventbusWeb.LegalController do
  use EventbusWeb, :controller

  def privacy(conn, _params), do: render(conn, :privacy, page_title: "Privacy Policy")
  def terms(conn, _params), do: render(conn, :terms, page_title: "Terms of Service")
end
