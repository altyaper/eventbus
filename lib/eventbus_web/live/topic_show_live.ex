defmodule EventbusWeb.TopicShowLive do
  use EventbusWeb, :live_view

  alias Eventbus.{Events, Topics}

  @max_events 100

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    {:ok, _topic} = Topics.get_or_create_by_name(name)

    {:ok,
     socket
     |> assign(:page_title, name)
     |> assign(:name, name)
     |> assign(:listening, false)
     |> assign(:events, [])
     |> assign_payload_form(%{"payload" => ""})}
  end

  @impl true
  def handle_event("toggle_listening", _params, socket) do
    pubsub_topic = Events.pubsub_topic(socket.assigns.name)

    if socket.assigns.listening do
      Phoenix.PubSub.unsubscribe(Eventbus.PubSub, pubsub_topic)
      {:noreply, assign(socket, :listening, false)}
    else
      Phoenix.PubSub.subscribe(Eventbus.PubSub, pubsub_topic)
      {:noreply, assign(socket, :listening, true)}
    end
  end

  @impl true
  def handle_event("publish_test", %{"test" => %{"payload" => payload_input}}, socket) do
    case Jason.decode(payload_input) do
      {:ok, payload} ->
        {:ok, _event} = Events.publish(socket.assigns.name, payload)
        {:noreply, assign_payload_form(socket, %{"payload" => ""})}

      {:error, _reason} ->
        {:noreply,
         assign_payload_form(socket, %{"payload" => payload_input},
           errors: [payload: {"must be valid JSON", []}]
         )}
    end
  end

  @impl true
  def handle_info({:event, event}, socket) do
    events = [event | socket.assigns.events] |> Enum.take(@max_events)
    {:noreply, assign(socket, :events, events)}
  end

  defp assign_payload_form(socket, params, opts \\ []) do
    assign(socket, :form, to_form(params, Keyword.put(opts, :as, "test")))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@name}
        <:subtitle>
          <.link navigate={~p"/"}>&larr; All topics</.link>
        </:subtitle>
        <:actions>
          <.button phx-click="toggle_listening" variant="primary">
            {if @listening, do: "Stop listening", else: "Start listening"}
          </.button>
        </:actions>
      </.header>

      <.form for={@form} phx-submit="publish_test" class="flex items-end gap-2 mt-6">
        <.input
          field={@form[:payload]}
          label="Publish a test event (JSON)"
          placeholder={~s({"hello": "world"})}
        />
        <.button>Publish</.button>
      </.form>

      <div class="mt-6 space-y-2">
        <p :if={@events == []} class="text-base-content/60">
          {if @listening, do: "Waiting for events...", else: "Not listening."}
        </p>
        <div :for={event <- @events} class="rounded-box bg-base-200 p-3">
          <div class="text-xs text-base-content/60">{event["published_at"]}</div>
          <pre class="text-sm whitespace-pre-wrap">{Jason.encode!(event["payload"], pretty: true)}</pre>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
