defmodule Eventbus.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:chat_users) do
      add :application_id, references(:applications, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :display_name, :string, null: false
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_users, [:application_id, :external_id])

    create table(:chat_rooms) do
      add :application_id, references(:applications, on_delete: :delete_all), null: false
      add :name, :string
      add :type, :string, null: false
      # "<min user id>:<max user id>" for direct rooms, so a pair has one room.
      add :direct_key, :string
      add :created_by_id, references(:chat_users, on_delete: :nilify_all)
      # No foreign key: messages are only ever removed together with their
      # room, and a cycle with chat_messages would complicate that cascade.
      add :last_message_id, :bigint
      add :last_message_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:chat_rooms, [:application_id, :direct_key])
    create index(:chat_rooms, [:application_id, :last_message_at])

    create table(:chat_room_members) do
      add :room_id, references(:chat_rooms, on_delete: :delete_all), null: false
      add :chat_user_id, references(:chat_users, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime, inserted_at: :joined_at)
    end

    create unique_index(:chat_room_members, [:room_id, :chat_user_id])
    create index(:chat_room_members, [:chat_user_id])

    create table(:chat_messages) do
      add :room_id, references(:chat_rooms, on_delete: :delete_all), null: false
      add :sender_id, references(:chat_users, on_delete: :delete_all), null: false
      add :text, :text, null: false
      add :metadata, :map, null: false, default: %{}
      add :reply_to_id, references(:chat_messages, on_delete: :nilify_all)
      add :client_ref, :string
      add :edited_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_messages, [:room_id, :id])
    create unique_index(:chat_messages, [:sender_id, :client_ref])
  end
end
