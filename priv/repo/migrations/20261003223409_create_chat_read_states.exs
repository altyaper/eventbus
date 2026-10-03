defmodule Eventbus.Repo.Migrations.CreateChatReadStates do
  use Ecto.Migration

  def change do
    create table(:chat_read_states) do
      add :room_id, references(:chat_rooms, on_delete: :delete_all), null: false
      add :chat_user_id, references(:chat_users, on_delete: :delete_all), null: false
      # No foreign key, like chat_rooms.last_message_id: messages only go away
      # with their room.
      add :last_read_message_id, :bigint, null: false

      timestamps(type: :utc_datetime, inserted_at: false)
    end

    create unique_index(:chat_read_states, [:room_id, :chat_user_id])
  end
end
