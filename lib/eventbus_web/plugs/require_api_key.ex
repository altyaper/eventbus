defmodule EventbusWeb.Plugs.RequireApiKey do
  @moduledoc """
  Requires `Authorization: Bearer <api key>` on HTTP publish requests (see
  `Eventbus.Settings.api_key/0`).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected_key = Eventbus.Settings.api_key()

    with ["Bearer " <> given_key] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(given_key, expected_key) do
      conn
    else
      _other ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "unauthorized"})
        |> halt()
    end
  end
end
