defmodule EventbusWeb.ChatDemoLive do
  @moduledoc """
  Try an app's chat as one of its users, through the JS SDK the way a
  consuming app would. The superadmin picks a user id to act as; this page
  stands in for the app's backend and mints tokens for the SDK (the hook asks
  for one over `pushEvent`, so expiry refreshes work too). Open it in two
  windows as different users to chat with yourself.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents

  alias Eventbus.Applications
  alias Eventbus.Accounts.Scope
  alias Eventbus.Chat.{Broadcast, Caller, Messages, Rooms, Serializer, Tokens, Users}

  @bot "eventbus-bot"

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    cond do
      not Scope.superadmin?(socket.assigns.current_scope) ->
        {:ok,
         socket
         |> put_flash(:error, "Only the superadmin can open that page.")
         |> push_navigate(to: ~p"/apps/#{slug}/chat")}

      app = Applications.get_app_by_slug(slug) ->
        {:ok,
         socket
         |> assign(:page_title, "Chat demo · #{app.slug}")
         |> assign(:app, app)
         |> assign(:acting_as, nil)
         |> assign_act_form(%{"user_id" => "", "display_name" => ""})}

      true ->
        {:ok,
         socket
         |> put_flash(:error, "There's no application #{slug}.")
         |> push_navigate(to: ~p"/apps")}
    end
  end

  @impl true
  def handle_event("act_as", %{"act" => params}, socket) do
    user_id = String.trim(params["user_id"] || "")
    display_name = String.trim(params["display_name"] || "")
    display_name = if display_name == "", do: user_id, else: display_name

    case Tokens.mint(socket.assigns.app, %{external_id: user_id, display_name: display_name}) do
      {:ok, %{user: user}} ->
        {:noreply, assign(socket, :acting_as, user)}

      {:error, changeset} ->
        errors =
          Enum.map(changeset.errors, fn
            {:external_id, error} -> {:user_id, error}
            other -> other
          end)

        {:noreply, assign_act_form(socket, params, errors)}
    end
  end

  def handle_event("stop_acting", _params, socket),
    do: {:noreply, assign(socket, :acting_as, nil)}

  # The hook's getToken: what the app's backend would get from
  # POST /api/chat/tokens.
  def handle_event("token", _params, %{assigns: %{acting_as: %{} = user}} = socket) do
    attrs = %{external_id: user.external_id, display_name: user.display_name}
    {:ok, minted} = Tokens.mint(socket.assigns.app, attrs)
    {:reply, Serializer.token(socket.assigns.app, minted), socket}
  end

  def handle_event("token", _params, socket), do: {:reply, %{error: "not acting"}, socket}

  def handle_event("seed", _params, %{assigns: %{acting_as: %{} = user}} = socket) do
    seed(socket.assigns.app, user)
    {:noreply, put_flash(socket, :info, "Added sample rooms for #{user.display_name}.")}
  end

  # A public room, a group room and a direct room with a bot, each with a
  # message, so there's something to look at. Joining is idempotent.
  defp seed(app, user) do
    {:ok, bot} = Users.upsert_user(app, %{external_id: @bot, display_name: "eventbus bot"})
    bot_caller = Caller.new(app, bot)
    rooms = Rooms.list_app_rooms(app)

    general = find_or_create(app, rooms, "general", "public", bot)
    team = find_or_create(app, rooms, "demo-team", "group", bot)
    {:ok, direct, events} = Rooms.create_direct_room(app, user.external_id, @bot)
    Broadcast.dispatch(app, events)

    for room <- [general, team] do
      {:ok, _member, events} = Rooms.add_member(app, room, user.external_id)
      Broadcast.dispatch(app, events)
    end

    for {room, text} <- [
          {general, "Welcome to #general, #{user.display_name}! Anyone in the app can join."},
          {team, "This is a group room: only members can see it."},
          {direct, "Hi #{user.display_name}, this is a direct room. Try a reaction or a reply."}
        ] do
      {:ok, _message, events} = Messages.send_message(bot_caller, room, %{"text" => text})
      Broadcast.dispatch(app, events)
    end
  end

  defp find_or_create(app, rooms, name, type, bot) do
    case Enum.find(rooms, &(&1.name == name and &1.type == type)) do
      nil ->
        {:ok, room, events} =
          Rooms.create_room(app, %{name: name, type: type}, created_by: bot.external_id)

        Broadcast.dispatch(app, events)
        room

      room ->
        room
    end
  end

  defp assign_act_form(socket, params, errors \\ []) do
    assign(socket, :act_form, to_form(params, as: "act", errors: errors))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:apps}>
      <.app_shell app={@app} active={:chat} superadmin?={true} crumb="Demo" crumb_parent={:chat}>
        <%= if @acting_as do %>
          <div class="mb-4 flex flex-wrap items-center gap-3">
            <p class="text-sm text-base-content/60">
              Chatting as
              <span class="font-semibold text-base-content">{@acting_as.display_name}</span>
              <code class="font-mono text-xs">({@acting_as.external_id})</code>
              through the JS SDK.
            </p>
            <div class="ml-auto flex gap-2">
              <button
                id="seed-rooms"
                type="button"
                phx-click="seed"
                class="inline-flex items-center gap-1.5 rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-medium transition-colors hover:bg-base-content/5"
              >
                <.icon name="hero-sparkles-micro" class="size-4" /> Seed sample rooms
              </button>
              <button
                id="stop-acting"
                type="button"
                phx-click="stop_acting"
                class="inline-flex items-center gap-1.5 rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-medium transition-colors hover:bg-base-content/5"
              >
                <.icon name="hero-arrow-left-start-on-rectangle-micro" class="size-4" /> Switch user
              </button>
            </div>
          </div>
          <%!-- The SDK and the demo's render functions own this element. --%>
          <div
            id={"chat-demo-#{@acting_as.id}"}
            phx-hook="ChatDemo"
            phx-update="ignore"
            data-socket-url="/socket"
          >
          </div>
        <% else %>
          <.card id="act-as">
            <h2 class="flex items-center gap-2 font-semibold">
              <.icon name="hero-user-circle" class="size-5 text-primary" /> Act as a user
            </h2>
            <p class="mt-1 text-sm text-base-content/50">
              This page plays {@app.slug}'s backend: it mints a chat token for the user you name, as
              <code class="font-mono">POST /api/chat/tokens</code>
              would. Open a second window as someone else to chat back.
            </p>
            <.form
              for={@act_form}
              id="act-form"
              phx-submit="act_as"
              class="mt-4 grid gap-2 sm:grid-cols-[1fr_1fr_auto] sm:items-start"
            >
              <.input field={@act_form[:user_id]} placeholder="user id, e.g. ann" autocomplete="off" />
              <.input
                field={@act_form[:display_name]}
                placeholder="display name, e.g. Ann"
                autocomplete="off"
              />
              <button
                id="start-acting"
                type="submit"
                class="mt-1 inline-flex items-center justify-center gap-1.5 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-95"
              >
                <.icon name="hero-chat-bubble-left-right-micro" class="size-4" /> Start chatting
              </button>
            </.form>
          </.card>
        <% end %>
      </.app_shell>
    </Layouts.app>
    """
  end
end
