defmodule Eventbus.Chat.Broadcast do
  @moduledoc """
  The only chat module that talks to `Phoenix.PubSub`. Contexts return the
  events a change caused, as `{:room, room, name, payload}` or
  `{:user, user, name, payload}`, and callers hand them to `dispatch/2`, so
  the domain never touches the transport.

  Subscribers receive `{:chat_event, name, payload}`.
  """

  alias Eventbus.Applications.App
  alias Eventbus.Chat.{Room, User}

  @pubsub Eventbus.PubSub

  @doc """
  The topic of one room, also its channel topic: `"chat:<slug>:<room_id>"`.
  """
  def room_topic(slug, room_id), do: "chat:#{slug}:#{room_id}"

  @doc """
  One user's topic for activity across their rooms, also its channel topic:
  `"chat_user:<slug>:<external_id>"`.
  """
  def user_topic(slug, external_id), do: "chat_user:#{slug}:#{external_id}"

  def subscribe_room(%App{slug: slug}, %Room{id: id}),
    do: Phoenix.PubSub.subscribe(@pubsub, room_topic(slug, id))

  def unsubscribe_room(%App{slug: slug}, %Room{id: id}),
    do: Phoenix.PubSub.unsubscribe(@pubsub, room_topic(slug, id))

  @doc """
  Broadcasts each event to its room or user topic in `app`.
  """
  def dispatch(%App{slug: slug}, events) do
    Enum.each(events, fn
      {:room, %Room{id: id}, name, payload} ->
        broadcast(room_topic(slug, id), name, payload)

      {:user, %User{} = user, name, payload} ->
        broadcast(user_topic(slug, user.external_id), name, payload)
    end)
  end

  @doc """
  Like `dispatch/2`, but not to the calling process, e.g. so a channel's own
  typing events don't come back to it.
  """
  def dispatch_from(%App{slug: slug}, events) do
    Enum.each(events, fn {:room, %Room{id: id}, name, payload} ->
      Phoenix.PubSub.broadcast_from(
        @pubsub,
        self(),
        room_topic(slug, id),
        {:chat_event, name, payload}
      )
    end)
  end

  defp broadcast(topic, name, payload),
    do: Phoenix.PubSub.broadcast(@pubsub, topic, {:chat_event, name, payload})
end
