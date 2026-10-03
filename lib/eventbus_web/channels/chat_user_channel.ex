defmodule EventbusWeb.ChatUserChannel do
  @moduledoc """
  A chat user's own channel, `"chat_user:<app slug>:<external id>"`, for the
  sidebar: the join reply is their room list, and activity across their rooms
  (`room.member.added`, `room.member.removed`, ...) arrives here without
  joining every room. Only that user's chat socket may join.
  """

  use Phoenix.Channel

  alias Eventbus.Origins
  alias Eventbus.Chat.{Rooms, Serializer}

  @impl true
  def join("chat_user:" <> rest, _params, %{assigns: %{chat_caller: caller}} = socket) do
    with [slug, external_id] <- String.split(rest, ":", parts: 2),
         true <- slug == caller.app.slug and external_id == caller.user.external_id,
         true <- Origins.allowed_for_app?(socket.assigns.origin, slug) || {:error, :origin} do
      rooms = caller |> Rooms.list_user_rooms() |> Enum.map(&Serializer.room_summary/1)
      {:ok, %{user: Serializer.user(caller.user), rooms: rooms}, socket}
    else
      {:error, :origin} -> {:error, %{reason: "origin not allowed"}}
      _other_user -> {:error, %{reason: "forbidden"}}
    end
  end

  def join("chat_user:" <> _rest, _params, _anonymous), do: {:error, %{reason: "unauthorized"}}

  @impl true
  def handle_info({:chat_event, name, payload}, socket) do
    push(socket, name, payload)
    {:noreply, socket}
  end
end
