defmodule EventbusWeb.TopicShowLive do
  @moduledoc """
  One topic inside its app: watch its events live and publish test events.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents

  alias Eventbus.{Applications, Events, Topics}

  @max_events 100

  @impl true
  def mount(%{"slug" => slug, "name" => name}, _session, socket) do
    # Topics belong to applications, so the page never creates them.
    with {:app, app} when not is_nil(app) <-
           {:app, Applications.get_owned_app(socket.assigns.current_scope, slug)},
         %{application_id: app_id} when app_id == app.id <- Topics.get_topic_by_name(name) do
      {:ok,
       socket
       |> assign(:page_title, name)
       |> assign(:app, app)
       |> assign(:name, name)
       |> assign(:listening, false)
       |> assign(:events, [])
       |> assign_payload_form(%{"payload" => ""})}
    else
      {:app, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "There's no application #{slug}.")
         |> push_navigate(to: ~p"/apps")}

      _missing_or_other_app ->
        {:ok,
         socket
         |> put_flash(:error, "Topic #{name} doesn't exist in #{slug}.")
         |> push_navigate(to: ~p"/apps/#{slug}/topics")}
    end
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

  # The topic's group on the topics page: "board" for "<slug>.board.x".
  defp parent_group(slug, name) do
    name
    |> String.replace_prefix(slug <> ".", "")
    |> String.split(".")
    |> Enum.drop(-1)
    |> Enum.join(".")
  end

  defp parent_path(slug, name) do
    case parent_group(slug, name) do
      "" -> ~p"/apps/#{slug}/topics"
      group -> ~p"/apps/#{slug}/topics?#{[group: group]}"
    end
  end

  defp parent_name(slug, name) do
    case parent_group(slug, name) do
      "" -> slug
      group -> "#{slug}.#{group}"
    end
  end

  defp assign_payload_form(socket, params, opts \\ []) do
    assign(socket, :form, to_form(params, Keyword.put(opts, :as, "test")))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:apps}>
      <.app_shell app={@app} active={:topics} crumb={@name}>
        <.header>
          <span class="font-mono">{@name}</span>
          <:subtitle>
            <.link id="topic-back" navigate={parent_path(@app.slug, @name)}>
              &larr; All {parent_name(@app.slug, @name)} topics
            </.link>
          </:subtitle>
          <:actions>
            <.button phx-click="toggle_listening" variant="primary">
              {if @listening, do: "Stop listening", else: "Start listening"}
            </.button>
          </:actions>
        </.header>

        <.form for={@form} phx-submit="publish_test" class="mt-6">
          <label for={@form[:payload].id} class="label mb-1 text-sm">
            Publish a test event (JSON)
          </label>
          <%!-- Label sits outside the row and items align to the top. .input's
               wrapper is a daisyUI fieldset with vertical padding and a bottom
               margin; zero them so the input's top edge is the row's top edge. --%>
          <div class="flex items-start gap-2">
            <div class="flex-1 [&_.fieldset]:mb-0 [&_.fieldset]:py-0">
              <.input field={@form[:payload]} placeholder={~s({"hello": "world"})} />
            </div>
            <.button>Publish</.button>
          </div>
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
      </.app_shell>
    </Layouts.app>
    """
  end
end
