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

  def message(%Message{sender: %User{} = sender} = message) do
    deleted? = not is_nil(message.deleted_at)

    %{
      id: message.id,
      room_id: message.room_id,
      sender: user(sender),
      text: if(deleted?, do: "", else: message.text),
      metadata: if(deleted?, do: %{}, else: message.metadata),
      reply_to: nil,
      client_ref: message.client_ref,
      reactions: [],
      edited_at: message.edited_at,
      deleted_at: message.deleted_at,
      inserted_at: message.inserted_at
    }
  end

  @doc """
  One entry of a user's room list (see `Eventbus.Chat.Rooms.list_user_rooms/1`):
  the room, its latest message, and for direct rooms both members.
  """
  def room_summary(%{room: room, last_message: last_message, members: members}) do
    room
    |> room()
    |> Map.merge(%{
      last_message: last_message && message(last_message),
      members: Enum.map(members, &member/1)
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
