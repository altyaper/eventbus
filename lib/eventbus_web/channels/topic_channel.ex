defmodule EventbusWeb.TopicChannel do
  use Phoenix.Channel

  alias Eventbus.{Events, Topics}

  @impl true
  def join("topic:" <> name, _params, socket) do
    if Topics.valid_name?(name) do
      {:ok, _topic} = Topics.get_or_create_by_name(name)
      {:ok, assign(socket, :topic_name, name)}
    else
      {:error, %{reason: "invalid topic name"}}
    end
  end

  @impl true
  def handle_in("publish", payload, socket) do
    {:ok, event} = Events.publish(socket.assigns.topic_name, payload)
    {:reply, {:ok, event}, socket}
  end

  @impl true
  def handle_info({:event, event}, socket) do
    push(socket, "event", event)
    {:noreply, socket}
  end
end
