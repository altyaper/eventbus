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

    with {:ok, minted} <- Tokens.mint(app, attrs) do
      conn
      |> put_status(:created)
      |> json(Serializer.token(app, minted))
    end
  end
end
