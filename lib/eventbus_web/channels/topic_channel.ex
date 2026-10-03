defmodule EventbusWeb.TopicChannel do
  @moduledoc """
  Listen-only channel: clients join `"topic:<name>"` and receive every event
  published to it. Publishing is HTTP-only, with application credentials.

  Joining doesn't create a topic row, so anonymous sockets can't add topics;
  listening works before a topic exists because delivery is PubSub-only.

  Browser sockets may only join topics of an app that allows their origin
  (or any topic, from an env origin); see `Eventbus.Origins`.
  """

  use Phoenix.Channel

  alias Eventbus.{Origins, Topics}

  @impl true
  def join("topic:" <> name, _params, socket) do
    cond do
      not Topics.valid_name?(name) ->
        {:error, %{reason: "invalid topic name"}}

      not Origins.allowed_for_topic?(socket.assigns[:origin], name) ->
        {:error, %{reason: "origin not allowed"}}

      true ->
        {:ok, assign(socket, :topic_name, name)}
    end
  end

  @impl true
  def handle_info({:event, event}, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end
end
