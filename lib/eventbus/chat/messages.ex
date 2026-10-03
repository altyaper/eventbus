defmodule Eventbus.Chat.Messages do
  @moduledoc """
  Chat messages: the database is the source of truth, realtime events only
  deliver. Pagination is by message id, which only grows.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Eventbus.Repo
  alias Eventbus.Chat.{Caller, Message, Room, Rooms, Serializer}

  @default_limit 50
  @max_limit 100

  def max_limit, do: @max_limit

  @doc """
  Stores a message from the caller in `room` and returns
  `{:ok, message, events}`. The caller must be a member. Sending again with
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
      Message.create_changeset(%Message{room_id: room.id, sender_id: caller.user.id}, attrs)

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
        message = %{message | sender: caller.user}

        {:ok, message,
         [
           {:room, room, "chat.message.created",
            %{room_id: room.id, message: Serializer.message(message)}}
         ]}

      {:error, :message, changeset, _changes} ->
        # The same client_ref sent twice at once: the unique index let one in.
        case client_ref && get_by_client_ref(caller, client_ref) do
          nil -> {:error, changeset}
          existing -> {:ok, existing, []}
        end
    end
  end

  defp get_by_client_ref(%Caller{user: user}, client_ref) when is_binary(client_ref) do
    Repo.one(
      from m in Message,
        where: m.sender_id == ^user.id and m.client_ref == ^client_ref,
        preload: :sender
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
    base = from m in Message, where: m.room_id == ^room_id, limit: ^(limit + 1), preload: :sender

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

  defp clamp_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp clamp_limit(_limit), do: @default_limit
end
