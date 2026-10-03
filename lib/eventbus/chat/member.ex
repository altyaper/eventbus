defmodule Eventbus.Chat.Member do
  @moduledoc """
  A chat user's membership of a room. Moderators may delete anyone's
  messages in the room.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(member moderator)

  schema "chat_room_members" do
    field :role, :string, default: "member"
    belongs_to :room, Eventbus.Chat.Room
    belongs_to :user, Eventbus.Chat.User, foreign_key: :chat_user_id

    timestamps(type: :utc_datetime, inserted_at: :joined_at)
  end

  def roles, do: @roles

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:room_id, :chat_user_id])
  end
end
