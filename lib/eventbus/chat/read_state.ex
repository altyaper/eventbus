defmodule Eventbus.Chat.ReadState do
  @moduledoc """
  How far a user has read a room: everything up to `last_read_message_id`.
  """

  use Ecto.Schema

  schema "chat_read_states" do
    field :last_read_message_id, :integer
    belongs_to :room, Eventbus.Chat.Room
    belongs_to :user, Eventbus.Chat.User, foreign_key: :chat_user_id

    timestamps(type: :utc_datetime, inserted_at: false)
  end
end
