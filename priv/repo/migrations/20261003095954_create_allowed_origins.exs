defmodule Eventbus.Repo.Migrations.CreateAllowedOrigins do
  use Ecto.Migration

  def change do
    create table(:allowed_origins) do
      add :origin, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:allowed_origins, [:origin])
  end
end
