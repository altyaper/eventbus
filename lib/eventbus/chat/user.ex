defmodule Eventbus.Chat.User do
  @moduledoc """
  A chat user of an application. eventbus never authenticates them: the
  app's backend vouches for them when it mints a token, and `external_id` is
  the app's own id for that user.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @external_id_format ~r/^[A-Za-z0-9._@+:-]+$/

  schema "chat_users" do
    field :external_id, :string
    field :display_name, :string
    field :avatar_url, :string
    belongs_to :app, Eventbus.Applications.App, foreign_key: :application_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Checks an external id without touching the database.
  """
  def valid_external_id?(id) when is_binary(id),
    do: byte_size(id) <= 255 and Regex.match?(@external_id_format, id)

  def valid_external_id?(_id), do: false

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:external_id, :display_name, :avatar_url])
    |> update_change(:display_name, &String.trim/1)
    |> validate_required([:external_id, :display_name])
    |> validate_length(:external_id, max: 255)
    |> validate_format(:external_id, @external_id_format,
      message: "must be letters, digits or . _ @ + : -"
    )
    |> validate_length(:display_name, max: 100)
    |> validate_length(:avatar_url, max: 2000)
    |> unique_constraint([:application_id, :external_id])
  end
end
