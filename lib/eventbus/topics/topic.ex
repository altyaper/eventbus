defmodule Eventbus.Topics.Topic do
  use Ecto.Schema
  import Ecto.Changeset

  @name_format ~r/^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/

  schema "topics" do
    field :name, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Checks whether `name` matches the allowed topic-name format, without
  touching the database (so it can back both the HTTP API and the LiveView
  create form's client-side feedback).
  """
  def valid_name?(name) when is_binary(name), do: Regex.match?(@name_format, name)
  def valid_name?(_name), do: false

  @doc false
  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_format(:name, @name_format,
      message: "must be lowercase alphanumeric with '.', '-', '_'"
    )
    |> unique_constraint(:name)
  end
end
