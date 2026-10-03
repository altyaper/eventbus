defmodule Eventbus.Chat.Reaction do
  @moduledoc """
  One user's emoji reaction to a message. A user can add each emoji to a
  message once; emoji come from a fixed list (`Eventbus.Chat.Reactions`).
  """

  use Ecto.Schema

  schema "chat_message_reactions" do
    field :emoji, :string
    belongs_to :message, Eventbus.Chat.Message
    belongs_to :user, Eventbus.Chat.User, foreign_key: :chat_user_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
