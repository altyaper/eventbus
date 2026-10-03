defmodule Eventbus.Chat.Messages do
  @moduledoc """
  Chat messages: the database is the source of truth, realtime events only
  deliver. Pagination is by message id, which only grows.

  Authors edit their own messages; authors and the room's moderators delete
  (softly: the row stays, so ordering and replies keep working), and so can
  the app itself. Messages come back with what `Serializer.message/1` needs
  preloaded: sender, replied-to message and reactions.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.Chat.{Caller, Member, Message, Reaction, Room, Rooms, Serializer}

  @default_limit 50
  @max_limit 100

  def max_limit, do: @max_limit

  @doc """
  The associations a message needs to be serialized.
  """
  def preloads, do: [:sender, reply_to: :sender, reactions: {reactions_query(), :user}]

  defp reactions_query, do: from(r in Reaction, order_by: [asc: r.id])

  @doc """
  `room`'s message with `id`, preloaded, or `nil`.
  """
  def get_room_message(%Room{id: room_id}, id) when is_integer(id) do
    Repo.one(
      from m in Message, where: m.id == ^id and m.room_id == ^room_id, preload: ^preloads()
    )
  end

  def get_room_message(_room, _id), do: nil

  @doc """
  Stores a message from the caller in `room` and returns
  `{:ok, message, events}`: `chat.message.created` to the room and
  `room.activity` to each member. The caller must be a member. Sending again with
  the same `client_ref` returns the stored message and no events, so retries
  can't duplicate.
  """
  def send_message(%Caller{user: user} = caller, %Room{} = room, attrs) do
    client_ref = attrs[:client_ref] || attrs["client_ref"]

    cond do
      not Rooms.member?(room, user) -> {:error, :not_found}
      existing = client_ref && get_by_client_ref(caller, client_ref) -> {:ok, existing, []}
      true -> insert_message(caller, room, attrs, client_ref)
    end
  end

  defp insert_message(caller, room, attrs, client_ref) do
    changeset =
      %Message{room_id: room.id, sender_id: caller.user.id}
      |> Message.create_changeset(attrs)
      |> validate_reply_to(room)

    Multi.new()
    |> Multi.insert(:message, changeset)
    |> Multi.update_all(
      :room,
      fn %{message: message} ->
        from r in Room,
          where: r.id == ^room.id,
          update: [set: [last_message_id: ^message.id, last_message_at: ^message.inserted_at]]
      end,
      []
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message}} ->
        message = Repo.preload(%{message | sender: caller.user}, preloads())
        {:ok, message, created_events(room, message)}

      {:error, :message, changeset, _changes} ->
        # The same client_ref sent twice at once: the unique index let one in.
        case client_ref && get_by_client_ref(caller, client_ref) do
          nil -> {:error, changeset}
          existing -> {:ok, existing, []}
        end
    end
  end

  # Replies must point at a live message of the same room.
  defp validate_reply_to(changeset, room) do
    Ecto.Changeset.validate_change(changeset, :reply_to_id, fn :reply_to_id, id ->
      if Repo.exists?(
           from m in Message,
             where: m.id == ^id and m.room_id == ^room.id and is_nil(m.deleted_at)
         ),
         do: [],
         else: [reply_to_id: "must be a message in this room"]
    end)
  end

  # The full message to the room; a preview to every member's own topic, for
  # sidebars showing rooms they haven't opened.
  defp created_events(room, message) do
    activity = %{
      room_id: room.id,
      message: Serializer.message_preview(message),
      last_message_at: message.inserted_at
    }

    [
      {:room, room, "chat.message.created",
       %{room_id: room.id, message: Serializer.message(message)}}
      | for(user <- Rooms.list_member_users(room), do: {:user, user, "room.activity", activity})
    ]
  end

  defp get_by_client_ref(%Caller{user: user}, client_ref) when is_binary(client_ref) do
    Repo.one(
      from m in Message,
        where: m.sender_id == ^user.id and m.client_ref == ^client_ref,
        preload: ^preloads()
    )
  end

  defp get_by_client_ref(_caller, _client_ref), do: nil

  @doc """
  A page of `room`'s messages, oldest first, as `%{messages, has_more}`.

    * `before: id` - the page just before that message; `has_more` means
      there are older ones
    * `after: id` - the messages after that one, to fill a gap after a
      reconnect; `has_more` means the gap is longer than the page
    * neither - the newest page; `has_more` means there are older ones

  `limit` defaults to #{@default_limit} and is capped at #{@max_limit}.
  """
  def list_messages(%Room{id: room_id}, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> clamp_limit()

    base =
      from m in Message, where: m.room_id == ^room_id, limit: ^(limit + 1), preload: ^preloads()

    {messages, newest_first?} =
      case Keyword.get(opts, :after) do
        after_id when is_integer(after_id) ->
          {Repo.all(from m in base, where: m.id > ^after_id, order_by: [asc: m.id]), false}

        _other ->
          query =
            case Keyword.get(opts, :before) do
              before_id when is_integer(before_id) -> from m in base, where: m.id < ^before_id
              _none -> base
            end

          {Repo.all(from m in query, order_by: [desc: m.id]), true}
      end

    page = Enum.take(messages, limit)

    %{
      messages: if(newest_first?, do: Enum.reverse(page), else: page),
      has_more: length(messages) > limit
    }
  end

  @doc """
  Changes the text of the caller's own message `id` in `room`. Others get
  `:forbidden`; missing or deleted messages `:not_found`.
  """
  def edit_message(%Caller{user: user}, %Room{} = room, id, attrs) do
    case get_room_message(room, id) do
      %Message{deleted_at: nil, sender_id: sender_id} = message when sender_id == user.id ->
        with {:ok, message} <- message |> Message.edit_changeset(attrs) |> Repo.update() do
          {:ok, message, [message_event(room, "chat.message.updated", message)]}
        end

      %Message{deleted_at: nil} ->
        {:error, :forbidden}

      _missing_or_deleted ->
        {:error, :not_found}
    end
  end

  @doc """
  Soft-deletes message `id` in `room`: the caller's own, or anyone's if they
  moderate the room. Deleting again is a no-op without events.
  """
  def delete_message(%Caller{user: user}, %Room{} = room, id) do
    case get_room_message(room, id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: sender_id} = message ->
        if sender_id == user.id or moderator?(room, user),
          do: soft_delete(room, message),
          else: {:error, :forbidden}
    end
  end

  @doc """
  Soft-deletes message `id` in `room` on the app's behalf (its backend, or
  the eventbus admin moderating).
  """
  def delete_message_as_app(%App{id: app_id}, %Room{application_id: app_id} = room, id) do
    case get_room_message(room, id) do
      nil -> {:error, :not_found}
      message -> soft_delete(room, message)
    end
  end

  defp soft_delete(_room, %Message{deleted_at: %DateTime{}} = message), do: {:ok, message, []}

  defp soft_delete(room, message) do
    {:ok, message} =
      message |> Ecto.Changeset.change(deleted_at: DateTime.utc_now()) |> Repo.update()

    {:ok, message, [message_event(room, "chat.message.deleted", message)]}
  end

  defp moderator?(room, user) do
    Repo.exists?(
      from m in Member,
        where: m.room_id == ^room.id and m.chat_user_id == ^user.id and m.role == "moderator"
    )
  end

  defp message_event(room, name, message),
    do: {:room, room, name, %{room_id: room.id, message: Serializer.message(message)}}

  defp clamp_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp clamp_limit(_limit), do: @default_limit
end
