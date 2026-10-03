defmodule Eventbus.Topics.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  alias Eventbus.Applications.App

  @name_format ~r/^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/

  schema "topics" do
    field :name, :string
    belongs_to :app, App, foreign_key: :application_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Checks whether `name` matches the allowed topic-name format, without
  touching the database (so it can back both the HTTP API and the channel
  join).
  """
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_format, name)
  def valid_name?(_name), do: false

  @doc """
  Changeset for a topic of `app`: the name must be `"<slug>.<rest>"`.
  """
  def changeset(topic, %App{} = app, attrs) do
    topic
    |> cast(attrs, [:name])
    |> put_change(:application_id, app.id)
    |> validate_required([:name])
    |> validate_format(:name, @name_format,
      message: "must be lowercase alphanumeric with '.', '-', '_'"
    )
    |> validate_change(:name, fn :name, name ->
      if String.starts_with?(name, app.slug <> "."),
        do: [],
        else: [name: "must start with #{app.slug}."]
    end)
    |> unique_constraint(:name)
    |> foreign_key_constraint(:application_id)
  end
end
