defmodule EventbusWeb.TopicTokenController do
  @moduledoc """
  Topic tokens for an app's backend (see `Eventbus.TopicTokens`):
  `POST /api/tokens` mints one for a user, `POST /api/tokens/revoke` takes
  topics away from a user.
  """

  use EventbusWeb, :controller

  alias Eventbus.TopicTokens

  action_fallback EventbusWeb.ChatFallbackController

  def create(%{assigns: %{current_app: app}} = conn, params) do
    with {:ok, %{token: token, expires_at: expires_at}} <- TopicTokens.mint(app, params) do
      conn
      |> put_status(:created)
      |> json(%{token: token, expires_at: expires_at})
    end
  end

  def revoke(%{assigns: %{current_app: app}} = conn, params) do
    with :ok <- TopicTokens.revoke(app, params["user_id"], params["grants"]) do
      send_resp(conn, :no_content, "")
    end
  end
end
