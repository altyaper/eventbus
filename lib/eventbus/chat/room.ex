defmodule Eventbus.Chat.Room do
  @moduledoc """
  A chat room of an application, the realtime boundary for messages,
  presence and typing. `direct` rooms have exactly two members and no name;
  `group` rooms need a membership; `public` rooms let any of the app's chat
  users join.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Eventbus.Chat.{Member, User}

  @types ~w(direct group public)

  schema "chat_rooms" do
    field :name, :string
    field :type, :string
    field :direct_key, :string
    field :last_message_id, :integer
    field :last_message_at, :utc_datetime_usec
    belongs_to :app, Eventbus.Applications.App, foreign_key: :application_id
    belongs_to :created_by, User
    has_many :members, Member
    # Only set by Rooms.list_app_rooms/1.
    field :members_count, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  def types, do: @types

  @doc """
  Changeset for a group or public room.
  """
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :type])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, ~w(group public))
    |> validate_length(:name, max: 100)
  end

  @doc """
  The key that makes a pair of users have a single direct room.
  """
  def direct_key(%User{id: a}, %User{id: b}) when is_integer(a) and is_integer(b),
    do: "#{min(a, b)}:#{max(a, b)}"
end
