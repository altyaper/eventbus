defmodule Eventbus.Chat.Tokens do
  @moduledoc """
  Short-lived chat user tokens. An app's backend mints one for its logged-in
  user with the app's credentials and hands it to the browser, which connects
  with it; secrets never reach the browser. Verifying reloads the app and the
  user, so deleting either invalidates the token.
  """

  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.Chat.{Caller, User, Users}

  @salt "chat user"

  @doc """
  Upserts the user from `attrs` and returns `{:ok, %{token, expires_at, user}}`.
  """
  def mint(%App{} = app, attrs) do
    with {:ok, user} <- Users.upsert_user(app, attrs) do
      token = Phoenix.Token.sign(EventbusWeb.Endpoint, @salt, {app.id, user.id})
      expires_at = DateTime.add(DateTime.utc_now(:second), max_age(), :second)
      {:ok, %{token: token, expires_at: expires_at, user: user}}
    end
  end

  @doc """
  Returns `{:ok, caller}` for a valid, unexpired token whose app and user
  still exist, `:error` otherwise.
  """
  def verify(token) when is_binary(token) do
    with {:ok, {app_id, user_id}} <-
           Phoenix.Token.verify(EventbusWeb.Endpoint, @salt, token, max_age: max_age()),
         %App{} = app <- Repo.get(App, app_id),
         %User{application_id: ^app_id} = user <- Repo.get(User, user_id) do
      {:ok, Caller.new(app, user)}
    else
      _invalid -> :error
    end
  end

  def verify(_token), do: :error

  @doc """
  How long tokens last, in seconds (1 hour unless configured).
  """
  def max_age, do: Application.get_env(:eventbus, :chat_token_max_age, 3600)
end
