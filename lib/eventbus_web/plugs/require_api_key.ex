defmodule EventbusWeb.Plugs.RequireApiKey do
  @moduledoc """
  Requires `Authorization: Bearer <EVENTBUS_API_KEY>` on HTTP publish requests.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    expected_key = Application.fetch_env!(:eventbus, :api_key)

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
