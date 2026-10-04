defmodule Eventbus.Repo.Migrations.AddEmailAccountsAndAppOwners do
  @moduledoc """
  Switches users from usernames to emails and gives every application an
  owner.

  Existing installs have a superadmin without an email, and a migration
  can't ask for one, so it comes from `EVENTBUS_ADMIN_EMAIL`. The superadmin
  is marked confirmed and takes over every existing app.
  """

  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    alter table(:users) do
      add :email, :citext
      add :confirmed_at, :utc_datetime
      add :accepted_terms_at, :utc_datetime
    end

    alter table(:users_tokens) do
      add :sent_to, :string
    end

    alter table(:applications) do
      add :owner_id, references(:users, on_delete: :delete_all)
    end

    flush()
    backfill_existing_install()

    alter table(:users) do
      modify :email, :citext, null: false
      remove :username
    end

    alter table(:applications) do
      modify :owner_id, :bigint, null: false
    end

    create unique_index(:users, [:email])
    create index(:applications, [:owner_id])
  end

  def down do
    alter table(:users) do
      add :username, :string
    end

    flush()
    repo().query!("UPDATE users SET username = lower(split_part(email::text, '@', 1)) || id")

    alter table(:users) do
      modify :username, :string, null: false
      remove :email
      remove :confirmed_at
      remove :accepted_terms_at
    end

    create unique_index(:users, [:username])

    alter table(:users_tokens) do
      remove :sent_to
    end

    alter table(:applications) do
      remove :owner_id
    end
  end

  defp backfill_existing_install do
    %{rows: [[users]]} = repo().query!("SELECT count(*) FROM users")
    %{rows: [[apps]]} = repo().query!("SELECT count(*) FROM applications")

    cond do
      users > 0 ->
        email = admin_email!()

        repo().query!(
          """
          UPDATE users
          SET email = $1, confirmed_at = now(), accepted_terms_at = now()
          WHERE id = (SELECT min(id) FROM users WHERE role = 'superadmin')
          """,
          [email]
        )

        # Only the superadmin should exist, but don't fail on stragglers:
        # give them an address that can never receive mail.
        repo().query!("UPDATE users SET email = username || '@users.invalid' WHERE email IS NULL")

        repo().query!("""
        UPDATE applications
        SET owner_id = (SELECT min(id) FROM users WHERE role = 'superadmin')
        """)

      apps > 0 ->
        raise "applications exist but no user does: complete /setup before upgrading"

      true ->
        :fresh_install
    end
  end

  defp admin_email! do
    case System.get_env("EVENTBUS_ADMIN_EMAIL") do
      email when is_binary(email) and email != "" ->
        String.trim(email)

      _missing ->
        raise """
        EVENTBUS_ADMIN_EMAIL is not set. Users now log in with an email address: \
        set EVENTBUS_ADMIN_EMAIL to the superadmin's email and run the migration again.
        """
    end
  end
end
