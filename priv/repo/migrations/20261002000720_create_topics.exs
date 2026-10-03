defmodule Eventbus.Repo.Migrations.CreateTopics do
  use Ecto.Migration

  def change do
    create table(:topics) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:topics, [:name])
  end
end
