defmodule Eventbus.Chat.Reactions do
  @moduledoc """
  Emoji reactions to messages. Emoji come from a fixed list, which keeps
  aggregation simple and stops reactions being used as a free-text channel.
  Adding a reaction you already have, or removing one you don't, changes
  nothing and has no events.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Chat.{Caller, Message, Reaction, Room, Rooms}

  @emoji ~w(👍 👎 ❤️ 😂 😮 😢 😡 🎉 🙏 🔥 👀 ✅ ❌ 💯 🚀 👏 🤔 😍 😅 🙌 💪 ✨ 🤝 👋 😊 😎 🥳 😬 🙈 ⭐)

  def allowed_emoji, do: @emoji

  @doc """
  Adds the caller's `emoji` to message `message_id` of `room`. The caller
  must be a member and the message not deleted.
  """
  def add_reaction(%Caller{} = caller, %Room{} = room, message_id, emoji) do
    with {:ok, message} <- fetch_target(caller, room, message_id, emoji) do
      {_count, inserted} =
        Repo.insert_all(
          Reaction,
          [
            %{
              message_id: message.id,
              chat_user_id: caller.user.id,
              emoji: emoji,
              inserted_at: DateTime.utc_now()
            }
          ],
          on_conflict: :nothing,
          returning: [:id]
        )

      {:ok, events(room, message, caller, emoji, "chat.reaction.added", inserted != [])}
    end
  end

  @doc """
  Removes the caller's `emoji` from message `message_id` of `room`.
  """
  def remove_reaction(%Caller{} = caller, %Room{} = room, message_id, emoji) do
    with {:ok, message} <- fetch_target(caller, room, message_id, emoji) do
      {count, _} =
        Repo.delete_all(
          from r in Reaction,
            where:
              r.message_id == ^message.id and r.chat_user_id == ^caller.user.id and
                r.emoji == ^emoji
        )

      {:ok, events(room, message, caller, emoji, "chat.reaction.removed", count > 0)}
    end
  end

  defp fetch_target(caller, room, message_id, emoji) do
    cond do
      emoji not in @emoji or not is_integer(message_id) ->
        {:error, :invalid}

      not Rooms.member?(room, caller.user) ->
        {:error, :not_found}

      true ->
        case Repo.get_by(Message, id: message_id, room_id: room.id) do
          %Message{deleted_at: nil} = message -> {:ok, message}
          _missing_or_deleted -> {:error, :not_found}
        end
    end
  end

  defp events(_room, _message, _caller, _emoji, _name, false = _changed), do: []

  defp events(room, message, caller, emoji, name, true) do
    [
      {:room, room, name,
       %{room_id: room.id, message_id: message.id, user_id: caller.user.external_id, emoji: emoji}}
    ]
  end
end
