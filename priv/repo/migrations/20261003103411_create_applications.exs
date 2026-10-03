defmodule Eventbus.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def up do
    create table(:applications) do
      add :slug, :string, null: false
      add :client_id, :string, null: false
      add :secret_hash, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:applications, [:slug])
    create unique_index(:applications, [:client_id])

    # Every topic now belongs to an application. Existing topics have none,
    # so start clean; publishers recreate topics on their next publish.
    execute "DELETE FROM topics"

    alter table(:topics) do
      add :application_id, references(:applications, on_delete: :delete_all), null: false
    end

    create index(:topics, [:application_id])
  end

  def down do
    alter table(:topics) do
      remove :application_id
    end

    drop table(:applications)
  end
end
