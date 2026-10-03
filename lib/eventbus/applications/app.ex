defmodule Eventbus.Applications.App do
  @moduledoc """
  An application: owns the topics named `"<slug>.*"` and publishes to them
  with its own `client_id` and secret.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @slug_format ~r/^[a-z0-9]([a-z0-9_-]*[a-z0-9])?$/

  schema "applications" do
    field :slug, :string
    field :client_id, :string
    field :secret_hash, :string, redact: true
    # Only set on the struct returned when the secret is (re)generated; the
    # secret itself is never stored.
    field :secret, :string, virtual: true, redact: true

    has_many :topics, Eventbus.Topics.Topic, foreign_key: :application_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an application. The slug can't be changed later:
  it's the prefix of every topic name, so renaming would silently break
  publishers and listeners.
  """
  def create_changeset(app, attrs) do
    app
    |> cast(attrs, [:slug])
    |> update_change(:slug, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:slug])
    |> validate_length(:slug, max: 40)
    |> validate_format(:slug, @slug_format,
      message: "must be lowercase letters, digits, '-' or '_' (no dots)"
    )
    |> unsafe_validate_unique(:slug, Eventbus.Repo, message: "is already taken")
    |> unique_constraint(:slug, message: "is already taken")
  end
end
