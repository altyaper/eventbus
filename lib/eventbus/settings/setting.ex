defmodule Eventbus.Settings.Setting do
  use Ecto.Schema

  schema "settings" do
    field :key, :string
    field :value, :string

    timestamps(type: :utc_datetime)
  end
end
