defmodule Eventbus.Chat.ReadStates do
  @moduledoc """
  Read positions and unread counts. Clients mark a room read explicitly (when
  its newest message is in view), never per scroll; a position only moves
  forward.

  Unread messages are those after the user's position, sent by someone else,
  not deleted, and sent since the user joined, so joining a busy room doesn't
  start with its whole history unread.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Chat.{Caller, Member, Message, ReadState, Room}

  def get_read_state(%Room{id: room_id}, %{id: user_id}),
    do: Repo.get_by(ReadState, room_id: room_id, chat_user_id: user_id)

  @doc """
  Moves the caller's position in `room` up to `message_id`, which must be a
  message of that room. Returns `{:ok, read_state, events}`; marking an
  older or the same message changes nothing and has no events.
  """
  def mark_read(%Caller{user: user}, %Room{} = room, message_id) when is_integer(message_id) do
    with true <-
           Repo.exists?(from m in Message, where: m.id == ^message_id and m.room_id == ^room.id) ||
             {:error, :not_found} do
      case get_read_state(room, user) do
        %ReadState{last_read_message_id: last} = read_state when last >= message_id ->
          {:ok, read_state, []}

        _behind_or_none ->
          now = DateTime.utc_now(:second)

          {:ok, read_state} =
            Repo.insert(
              %ReadState{
                room_id: room.id,
                chat_user_id: user.id,
                last_read_message_id: message_id,
                updated_at: now
              },
              on_conflict:
                from(r in ReadState,
                  update: [
                    set: [
                      last_read_message_id:
                        fragment(
                          "GREATEST(?, EXCLUDED.last_read_message_id)",
                          r.last_read_message_id
                        ),
                      updated_at: ^now
                    ]
                  ]
                ),
              conflict_target: [:room_id, :chat_user_id],
              returning: true
            )

          unread = unread_counts(user, [room.id]) |> Map.get(room.id, 0)

          {:ok, read_state,
           [
             {:user, user, "read_state.updated",
              %{
                room_id: room.id,
                last_read_message_id: read_state.last_read_message_id,
                unread_count: unread
              }}
           ]}
      end
    end
  end

  def mark_read(_caller, _room, _message_id), do: {:error, :invalid}

  @doc """
  Unread counts of `user` in the given rooms, as `%{room_id => count}`;
  rooms with nothing unread are left out. One grouped query.
  """
  def unread_counts(_user, []), do: %{}

  def unread_counts(%{id: user_id}, room_ids) do
    Repo.all(
      from m in Message,
        join: mem in Member,
        on: mem.room_id == m.room_id and mem.chat_user_id == ^user_id,
        left_join: r in ReadState,
        on: r.room_id == m.room_id and r.chat_user_id == ^user_id,
        where:
          m.room_id in ^room_ids and m.sender_id != ^user_id and is_nil(m.deleted_at) and
            m.id > coalesce(r.last_read_message_id, 0) and m.inserted_at >= mem.joined_at,
        group_by: m.room_id,
        select: {m.room_id, count(m.id)}
    )
    |> Map.new()
  end
end
