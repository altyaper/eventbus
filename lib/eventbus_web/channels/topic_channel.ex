defmodule EventbusWeb.TopicChannel do
  @moduledoc """
  Listen-only channel: clients join `"topic:<name>"` and receive every event
  published to it. Publishing is HTTP-only, with application credentials.

  Joining doesn't create a topic row, so anonymous sockets can't add topics;
  listening works before a topic exists because delivery is PubSub-only.
  """

  use Phoenix.Channel

  alias Eventbus.Topics

  @impl true
  def join("topic:" <> name, _params, socket) do
    if Topics.valid_name?(name) do
      {:ok, assign(socket, :topic_name, name)}
    else
      {:error, %{reason: "invalid topic name"}}
    end
  end

  @impl true
  def handle_info({:event, event}, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end
end
