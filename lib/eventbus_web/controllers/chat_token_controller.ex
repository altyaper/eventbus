defmodule EventbusWeb.ChatTokenController do
  @moduledoc """
  `POST /api/chat/tokens`: an app's backend mints a chat token for one of its
  users, creating or updating the user's profile.
  """

  use EventbusWeb, :controller

  alias Eventbus.Chat.{Serializer, Tokens}

  action_fallback EventbusWeb.ChatFallbackController

  def create(%{assigns: %{current_app: app}} = conn, params) do
    attrs = %{
      external_id: params["user_id"],
      display_name: params["display_name"],
      avatar_url: params["avatar_url"]
    }

    with {:ok, %{token: token, expires_at: expires_at, user: user}} <- Tokens.mint(app, attrs) do
      conn
      |> put_status(:created)
      |> json(%{token: token, expires_at: expires_at, user: Serializer.user(user)})
    end
  end
end
