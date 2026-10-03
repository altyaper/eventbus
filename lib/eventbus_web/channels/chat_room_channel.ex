defmodule EventbusWeb.ChatRoomChannel do
  @moduledoc """
  One chat room, `"chat:<app slug>:<room id>"`. Only chat sockets (see
  `EventbusWeb.UserSocket`) of the room's app may join, from an origin the
  app allows, and only if they're a member or the room is public.

  Clients write with pushes that reply `{:ok, ...}` or
  `{:error, %{reason: "not_found" | "invalid" | "rate_limited"}}`; room events
  (`chat.message.created`, `chat.member.joined`, ...) arrive as pushes named
  after the event. Identity always comes from the socket's token.

  After joining, the socket is tracked in `Eventbus.Chat.Presence`
  (`presence_state` / `presence_diff` pushes). Typing lives in this process:
  `typing: true` broadcasts `chat.typing.started` at most every few seconds,
  and `chat.typing.stopped` follows on `typing: false`, a sent message, a
  closed socket, or a few seconds without a refresh, so a crashed client
  can't leave "is typing" behind.
  """

  use Phoenix.Channel

  alias Eventbus.Origins
  alias Eventbus.Chat.{Broadcast, Messages, Presence, ReadStates, Rooms, Serializer}

  # At most this many sends per socket in the window.
  @send_limit 10
  @send_window_ms 10_000

  @impl true
  def join("chat:" <> rest, params, %{assigns: %{chat_caller: caller}} = socket) do
    with [slug, room_id] <- String.split(rest, ":", parts: 2),
         true <- slug == caller.app.slug || {:error, :not_found},
         true <- Origins.allowed_for_app?(socket.assigns.origin, slug) || {:error, :origin},
         {:ok, room, events} <- Rooms.open_room(caller, room_id) do
      Broadcast.dispatch(caller.app, events)
      send(self(), :after_join)

      {:ok, join_reply(caller, room, params),
       socket |> assign(:room, room) |> assign(:send_times, []) |> assign(:typing, nil)}
    else
      {:error, :origin} -> {:error, %{reason: "origin not allowed"}}
      _not_found -> {:error, %{reason: "not_found"}}
    end
  end

  def join("chat:" <> _rest, _params, _anonymous), do: {:error, %{reason: "unauthorized"}}

  # Without `after`, the newest page. With it (the newest message the client
  # already has, sent again on every rejoin), the messages it missed; a gap
  # longer than a page is replaced by the newest page and flagged, so the
  # client starts over instead of showing a hole.
  defp join_reply(caller, room, params) do
    page =
      case params do
        %{"after" => after_id} when is_integer(after_id) ->
          case Messages.list_messages(room, after: after_id, limit: Messages.max_limit()) do
            %{has_more: true} -> room |> Messages.list_messages() |> Map.put(:gap_truncated, true)
            page -> Map.merge(page, %{has_more: false, gap_truncated: false})
          end

        _no_after ->
          room |> Messages.list_messages() |> Map.put(:gap_truncated, false)
      end

    %{
      room: Serializer.room(room),
      members: room |> Rooms.list_members() |> Enum.map(&Serializer.member/1),
      messages: Enum.map(page.messages, &Serializer.message/1),
      has_more: page.has_more,
      gap_truncated: page.gap_truncated,
      read_state: read_state(caller, room)
    }
  end

  defp read_state(caller, room) do
    %{
      last_read_message_id:
        case ReadStates.get_read_state(room, caller.user) do
          nil -> nil
          read_state -> read_state.last_read_message_id
        end
    }
  end

  @impl true
  def handle_in("message:send", params, socket) when is_map(params) do
    case take_send_slot(socket) do
      {:ok, socket} ->
        %{chat_caller: caller, room: room} = socket.assigns
        attrs = Map.take(params, ["text", "client_ref", "metadata"])

        case Messages.send_message(caller, room, attrs) do
          {:ok, message, events} ->
            Broadcast.dispatch(caller.app, events)
            {:reply, {:ok, %{message: Serializer.message(message)}}, stop_typing(socket)}

          {:error, reason} ->
            {:reply, error(reason), socket}
        end

      :rate_limited ->
        {:reply, error(:rate_limited), socket}
    end
  end

  def handle_in("history", params, socket) when is_map(params) do
    opts =
      [before: params["before"], limit: params["limit"]]
      |> Enum.filter(fn {_key, value} -> is_integer(value) end)

    page = Messages.list_messages(socket.assigns.room, opts)

    {:reply,
     {:ok, %{messages: Enum.map(page.messages, &Serializer.message/1), has_more: page.has_more}},
     socket}
  end

  def handle_in("typing", %{"typing" => true}, socket), do: {:noreply, start_typing(socket)}
  def handle_in("typing", %{"typing" => false}, socket), do: {:noreply, stop_typing(socket)}

  def handle_in("read", %{"message_id" => message_id}, socket) do
    %{chat_caller: caller, room: room} = socket.assigns

    case ReadStates.mark_read(caller, room, message_id) do
      {:ok, read_state, events} ->
        Broadcast.dispatch(caller.app, events)
        {:reply, {:ok, %{last_read_message_id: read_state.last_read_message_id}}, socket}

      {:error, reason} ->
        {:reply, error(reason), socket}
    end
  end

  def handle_in(_event, _params, socket), do: {:reply, error(:invalid), socket}

  # A removed member stops receiving the room straight away; a :normal stop
  # sends phx_close, so the client doesn't try to rejoin.
  @impl true
  def handle_info(:after_join, socket) do
    user = socket.assigns.chat_caller.user
    push(socket, "presence_state", Presence.list(socket))

    {:ok, _ref} =
      Presence.track(socket, user.external_id, %{
        display_name: user.display_name,
        avatar_url: user.avatar_url,
        online_at: System.system_time(:second)
      })

    {:noreply, socket}
  end

  # Only the latest refresh's timer counts; older ones are stale.
  def handle_info({:typing_expired, ref}, %{assigns: %{typing: %{ref: ref}}} = socket),
    do: {:noreply, stop_typing(socket)}

  def handle_info({:typing_expired, _stale}, socket), do: {:noreply, socket}

  def handle_info({:chat_event, "chat.member.left" = name, payload}, socket) do
    push(socket, name, payload)

    if payload.member.user.id == socket.assigns.chat_caller.user.external_id,
      do: {:stop, :normal, socket},
      else: {:noreply, socket}
  end

  def handle_info({:chat_event, name, payload}, socket) do
    push(socket, name, payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:typing], do: stop_typing(socket)
    :ok
  end

  # Broadcasts `started` when typing begins, and again while it goes on so
  # other clients (which drop a typist after a few seconds without news)
  # keep showing it; pushes the expiry back on every refresh.
  defp start_typing(socket) do
    now = System.monotonic_time(:millisecond)
    typing = socket.assigns.typing

    broadcast_at =
      if is_nil(typing) or now - typing.broadcast_at >= typing_throttle_ms() do
        broadcast_typing(socket, "chat.typing.started")
        now
      else
        typing.broadcast_at
      end

    if typing, do: Process.cancel_timer(typing.timer)
    ref = make_ref()
    timer = Process.send_after(self(), {:typing_expired, ref}, typing_ttl_ms())
    assign(socket, :typing, %{ref: ref, timer: timer, broadcast_at: broadcast_at})
  end

  defp stop_typing(%{assigns: %{typing: nil}} = socket), do: socket

  defp stop_typing(%{assigns: %{typing: typing}} = socket) do
    Process.cancel_timer(typing.timer)
    broadcast_typing(socket, "chat.typing.stopped")
    assign(socket, :typing, nil)
  end

  defp broadcast_typing(socket, name) do
    %{chat_caller: caller, room: room} = socket.assigns

    Broadcast.dispatch_from(caller.app, [
      {:room, room, name, %{room_id: room.id, user_id: caller.user.external_id}}
    ])
  end

  defp typing_ttl_ms, do: Application.get_env(:eventbus, :chat_typing_ttl_ms, 4_000)
  defp typing_throttle_ms, do: Application.get_env(:eventbus, :chat_typing_throttle_ms, 3_000)

  defp take_send_slot(socket) do
    now = System.monotonic_time(:millisecond)
    recent = Enum.filter(socket.assigns.send_times, &(now - &1 < @send_window_ms))

    if length(recent) < @send_limit,
      do: {:ok, assign(socket, :send_times, [now | recent])},
      else: :rate_limited
  end

  defp error(%Ecto.Changeset{} = changeset),
    do: {:error, %{reason: "invalid", errors: Serializer.errors(changeset)}}

  defp error(reason) when reason in [:not_found, :invalid, :rate_limited],
    do: {:error, %{reason: Atom.to_string(reason)}}
end
