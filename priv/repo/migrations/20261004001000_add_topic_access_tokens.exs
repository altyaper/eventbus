defmodule Eventbus.Repo.Migrations.AddTopicAccessTokens do
  use Ecto.Migration

  def change do
    alter table(:applications) do
      add :require_topic_tokens, :boolean, null: false, default: false
    end

    # One row per (app, user) after a full revocation: topic tokens minted
    # before `revoked_at` are refused.
    create table(:topic_revocations) do
      add :application_id, references(:applications, on_delete: :delete_all), null: false
      add :user_id, :string, null: false
      add :revoked_at, :utc_datetime_usec, null: false
    end

    create unique_index(:topic_revocations, [:application_id, :user_id])
  end
end
