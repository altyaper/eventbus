defmodule EventbusWeb.TopicsLive.Index do
  use EventbusWeb, :live_view

  alias Eventbus.Topics
  alias Eventbus.Topics.Topic

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Topics")
     |> assign(:form, to_form(Topics.change_topic(%Topic{})))
     |> assign(:topics, Topics.list_topics())}
  end

  @impl true
  def handle_event("create", %{"topic" => topic_params}, socket) do
    case Topics.create_topic(topic_params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Topics.change_topic(%Topic{})))
         |> assign(:topics, Topics.list_topics())}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Topics
        <:subtitle>Create a topic, then click one to start listening.</:subtitle>
      </.header>

      <.form for={@form} phx-submit="create" class="flex items-end gap-2 mt-6">
        <.input field={@form[:name]} label="New topic name" placeholder="changologs.logs" />
        <.button variant="primary">Create</.button>
      </.form>

      <.table
        id="topics"
        rows={@topics}
        row_click={fn topic -> JS.navigate(~p"/topics/#{topic.name}") end}
      >
        <:col :let={topic} label="Name">{topic.name}</:col>
        <:col :let={topic} label="Created">{topic.inserted_at}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
