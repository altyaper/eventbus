defmodule Eventbus.Repo.Migrations.CreateChatMessageReactions do
  use Ecto.Migration

  def change do
    create table(:chat_message_reactions) do
      add :message_id, references(:chat_messages, on_delete: :delete_all), null: false
      add :chat_user_id, references(:chat_users, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:chat_message_reactions, [:message_id, :chat_user_id, :emoji])
  end
end
