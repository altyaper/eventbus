defmodule Eventbus.Chat.Message do
  @moduledoc """
  A chat message. Deleting only sets `deleted_at`, so ordering and replies
  keep working; the serializer blanks deleted content.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @max_text 4000
  @max_metadata_bytes 4096

  schema "chat_messages" do
    field :text, :string
    field :metadata, :map, default: %{}
    field :client_ref, :string
    field :edited_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec
    belongs_to :room, Eventbus.Chat.Room
    belongs_to :sender, Eventbus.Chat.User
    belongs_to :reply_to, __MODULE__

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for a new message. Room and sender are set by the caller, never
  cast.
  """
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:text, :metadata, :client_ref])
    |> validate_text()
    |> validate_length(:client_ref, max: 100)
    |> validate_metadata()
    |> unique_constraint([:sender_id, :client_ref])
  end

  defp validate_text(changeset) do
    changeset
    |> update_change(:text, &String.trim/1)
    |> validate_required([:text])
    |> validate_length(:text, max: @max_text)
  end

  defp validate_metadata(changeset) do
    validate_change(changeset, :metadata, fn :metadata, metadata ->
      if byte_size(Jason.encode!(metadata)) <= @max_metadata_bytes,
        do: [],
        else: [metadata: "must be at most #{@max_metadata_bytes} bytes"]
    end)
  end
end
