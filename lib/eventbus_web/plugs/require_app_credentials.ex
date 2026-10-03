defmodule EventbusWeb.Plugs.RequireAppCredentials do
  @moduledoc """
  Requires `Authorization: Basic base64(client_id:secret)` from an
  application and assigns it as `:current_app`. Missing, malformed and wrong
  credentials all get the same 401, so the response doesn't reveal whether a
  client id exists.
  """

  import Plug.Conn

  alias Eventbus.Applications

  def init(opts), do: opts

  def call(conn, _opts) do
    with {client_id, secret} <- Plug.BasicAuth.parse_basic_auth(conn),
         {:ok, app} <- Applications.authenticate(client_id, secret) do
      assign(conn, :current_app, app)
    else
      _other ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
