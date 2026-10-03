defmodule Eventbus.Repo.Migrations.ScopeAllowedOriginsToApplications do
  use Ecto.Migration

  # Origins move from instance-wide to per application. Existing ones are
  # copied onto every app so browser clients that connect today keep working;
  # with no apps they're dropped.
  def up do
    alter table(:allowed_origins) do
      add :application_id, references(:applications, on_delete: :delete_all)
    end

    drop unique_index(:allowed_origins, [:origin])

    execute """
    INSERT INTO allowed_origins (origin, application_id, inserted_at, updated_at)
    SELECT o.origin, a.id, o.inserted_at, o.updated_at
    FROM allowed_origins o CROSS JOIN applications a
    WHERE o.application_id IS NULL
    """

    execute "DELETE FROM allowed_origins WHERE application_id IS NULL"

    execute "ALTER TABLE allowed_origins ALTER COLUMN application_id SET NOT NULL"

    create unique_index(:allowed_origins, [:application_id, :origin])
  end

  # Back to one instance-wide list: the union of every app's origins.
  def down do
    drop unique_index(:allowed_origins, [:application_id, :origin])

    execute """
    DELETE FROM allowed_origins o
    USING allowed_origins keep
    WHERE o.origin = keep.origin AND o.id > keep.id
    """

    alter table(:allowed_origins) do
      remove :application_id
    end

    create unique_index(:allowed_origins, [:origin])
  end
end
