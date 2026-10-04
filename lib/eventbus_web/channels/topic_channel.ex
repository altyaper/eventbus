defmodule EventbusWeb.TopicChannel do
  @moduledoc """
  Listen-only channel: clients join `"topic:<name>"` and receive every event
  published to it. Publishing is HTTP-only, with application credentials.

  Joining doesn't create a topic row, so anonymous sockets can't add topics;
  listening works before a topic exists because delivery is PubSub-only.

  Browser sockets may only join topics of an app that allows their origin
  (or any topic, from an env origin); see `Eventbus.Origins`.

  A `token` join param (see `Eventbus.TopicTokens`) must grant the topic;
  a bad one is refused even where anonymous joins are allowed. Apps with
  `require_topic_tokens` refuse joins without one. Token channels are closed
  when the app revokes the topic for their user.
  """

  use Phoenix.Channel

  alias Eventbus.{Origins, Topics, TopicTokens}

  @impl true
  def join("topic:" <> name, params, socket) do
    cond do
      not Topics.valid_name?(name) ->
        {:error, %{reason: "invalid topic name"}}

      not Origins.allowed_for_topic?(socket.assigns[:origin], name) ->
        {:error, %{reason: "origin not allowed"}}

      true ->
        authorize(name, params, assign(socket, :topic_name, name))
    end
  end

  defp authorize(name, %{"token" => token}, socket) do
    case TopicTokens.verify(token, name) do
      {:ok, %{app: app_id, sub: user_id}} ->
        Phoenix.PubSub.subscribe(Eventbus.PubSub, TopicTokens.subscriber_topic(app_id, user_id))
        {:ok, socket}

      {:error, :expired} ->
        {:error, %{reason: "token expired"}}

      {:error, :revoked} ->
        {:error, %{reason: "token revoked"}}

      {:error, :forbidden} ->
        {:error, %{reason: "forbidden"}}

      {:error, :invalid} ->
        {:error, %{reason: "invalid token"}}
    end
  end

  defp authorize(name, _params, socket) do
    [slug | _rest] = String.split(name, ".", parts: 2)

    if TopicTokens.required?(slug),
      do: {:error, %{reason: "unauthorized"}},
      else: {:ok, socket}
  end

  @impl true
  def handle_info({:event, event}, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end

  # A shutdown exit makes the client see the channel close instead of
  # rejoining.
  def handle_info({:revoke_topics, grants}, socket) do
    if TopicTokens.revoked_topic?(grants, socket.assigns.topic_name) do
      push(socket, "revoked", %{})
      {:stop, {:shutdown, :revoked}, socket}
    else
      {:noreply, socket}
    end
  end
end
