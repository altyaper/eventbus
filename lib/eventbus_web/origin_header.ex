defmodule EventbusWeb.OriginHeader do
  @moduledoc """
  Copies the request's `Origin` into the `x-eventbus-origin` header, so
  `EventbusWeb.UserSocket` can read it through `connect_info: [:x_headers]`
  (Phoenix exposes no other request headers to sockets) and channels can
  check it per app on join.

  Sockets are dispatched before any endpoint plug runs, so this wraps the
  endpoint's `call/2` instead of being a plug. Any client-sent copy is dropped
  first so it can't be spoofed; browsers can't forge `Origin` itself.
  """

  @header "x-eventbus-origin"

  def header, do: @header

  def put(%Plug.Conn{} = conn) do
    conn = Plug.Conn.delete_req_header(conn, @header)

    case Plug.Conn.get_req_header(conn, "origin") do
      [origin | _] -> Plug.Conn.put_req_header(conn, @header, origin)
      [] -> conn
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      defoverridable call: 2

      def call(conn, opts), do: super(EventbusWeb.OriginHeader.put(conn), opts)
    end
  end
end
