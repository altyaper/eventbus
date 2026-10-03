defmodule Eventbus.Chat.Serializer do
  @moduledoc """
  The JSON shapes chat sends to clients, shared by channel replies, pushed
  events and the HTTP API. Users are identified by their app's external id.
  Messages are always full snapshots, so applying one twice is harmless.
  """

  alias Eventbus.Chat.{Member, Message, Room, User}

  def user(%User{} = user) do
    %{id: user.external_id, display_name: user.display_name, avatar_url: user.avatar_url}
  end

  def member(%Member{user: %User{} = user} = member) do
    %{user: user(user), role: member.role, joined_at: member.joined_at}
  end

  def room(%Room{} = room) do
    %{
      id: room.id,
      name: room.name,
      type: room.type,
      last_message_at: room.last_message_at,
      inserted_at: room.inserted_at
    }
  end

  @doc """
  The full message: sender, a preview of the message it replies to, and its
  reactions as `[%{emoji, count, user_ids}]` in the order they were first
  used. Deleted messages keep their place but lose text, metadata and
  reactions. Needs `Eventbus.Chat.Messages.preloads/0`.
  """
  def message(%Message{sender: %User{} = sender} = message) do
    deleted? = not is_nil(message.deleted_at)

    %{
      id: message.id,
      room_id: message.room_id,
      sender: user(sender),
      text: if(deleted?, do: "", else: message.text),
      metadata: if(deleted?, do: %{}, else: message.metadata),
      reply_to: reply_to(message.reply_to),
      client_ref: message.client_ref,
      reactions: if(deleted?, do: [], else: reactions(message.reactions)),
      edited_at: message.edited_at,
      deleted_at: message.deleted_at,
      inserted_at: message.inserted_at
    }
  end

  defp reply_to(nil), do: nil

  defp reply_to(%Message{sender: %User{} = sender} = message) do
    deleted? = not is_nil(message.deleted_at)

    %{
      id: message.id,
      sender: user(sender),
      text: if(deleted?, do: "", else: String.slice(message.text, 0, 140)),
      deleted: deleted?
    }
  end

  defp reactions(reactions) when is_list(reactions) do
    reactions
    |> Enum.group_by(& &1.emoji)
    |> Enum.sort_by(fn {_emoji, [first | _]} -> first.id end)
    |> Enum.map(fn {emoji, group} ->
      %{emoji: emoji, count: length(group), user_ids: Enum.map(group, & &1.user.external_id)}
    end)
  end

  @doc """
  A short form of a message for room lists: who, when, and the start of the
  text.
  """
  def message_preview(%Message{sender: %User{} = sender} = message) do
    %{
      id: message.id,
      sender: user(sender),
      text: if(message.deleted_at, do: "", else: String.slice(message.text, 0, 140)),
      deleted: not is_nil(message.deleted_at),
      inserted_at: message.inserted_at
    }
  end

  @doc """
  One entry of a user's room list (see `Eventbus.Chat.Rooms.list_user_rooms/1`):
  the room, a preview of its latest message, its unread count, and for
  direct rooms both members.
  """
  def room_summary(%{room: room, last_message: last_message, members: members} = summary) do
    room
    |> room()
    |> Map.merge(%{
      last_message: last_message && message_preview(last_message),
      members: Enum.map(members, &member/1),
      unread_count: summary.unread_count
    })
  end

  @doc """
  Changeset errors as `%{field => [message]}`.
  """
  def errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
