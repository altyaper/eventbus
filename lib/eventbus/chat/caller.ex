defmodule Eventbus.Chat.Caller do
  @moduledoc """
  Who is acting in chat: a chat user of an application. Built from a verified
  token (or by the server-side API for a user the app names), never from a
  client payload.
  """

  alias Eventbus.Applications.App
  alias Eventbus.Chat.User

  @enforce_keys [:app, :user]
  defstruct [:app, :user]

  def new(%App{id: app_id} = app, %User{application_id: app_id} = user),
    do: %__MODULE__{app: app, user: user}
end
