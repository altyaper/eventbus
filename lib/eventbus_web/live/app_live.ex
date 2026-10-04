defmodule EventbusWeb.AppLive do
  @moduledoc """
  One application's pages, one `live_action` per section: topics, chat,
  credentials, origins and settings. Sections are patched, so the app is
  loaded once. Everyone sees topics and chat; the other sections and every
  change are superadmin-only.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents

  alias Eventbus.{Applications, Origins, Topics}
  alias Eventbus.Chat.{Broadcast, Rooms, Users}
  alias Eventbus.Accounts.Scope
  alias Eventbus.Origins.AllowedOrigin

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Applications.get_app_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "There's no application #{slug}.")
         |> push_navigate(to: ~p"/apps")}

      app ->
        {:ok,
         socket
         |> assign(:app, app)
         |> assign(:page_title, app.slug)
         |> assign(:superadmin?, Scope.superadmin?(socket.assigns.current_scope))
         |> assign(:secret, nil)
         |> stream_configure(:topics, dom_id: &"topic-#{&1.id}")
         |> stream_configure(:origins, dom_id: &"origin-#{&1.id}")
         |> stream_configure(:rooms, dom_id: &"room-#{&1.id}")}
    end
  end

  # mount found no app and is already navigating away.
  @impl true
  def handle_params(_params, _uri, socket) when not is_map_key(socket.assigns, :app),
    do: {:noreply, socket}

  def handle_params(_params, uri, socket) do
    action = socket.assigns.live_action

    cond do
      action == :index ->
        {:noreply,
         push_patch(socket, to: section_path(socket.assigns.app.slug, :topics), replace: true)}

      action in superadmin_sections() and not socket.assigns.superadmin? ->
        {:noreply,
         socket
         |> put_flash(:error, "Only the superadmin can open that page.")
         |> push_patch(to: section_path(socket.assigns.app.slug, :topics), replace: true)}

      true ->
        {:noreply, load_section(socket, action, uri)}
    end
  end

  defp load_section(socket, :topics, uri) do
    query = URI.parse(uri).query || ""
    group = Map.get(URI.decode_query(query), "group", "")
    group = if Topics.valid_name?(group), do: group, else: ""

    socket
    |> assign(:topic_group, group)
    |> assign(:topic_form, topic_form(%{"name" => ""}))
    |> load_topic_level()
  end

  # The secret is only ever shown right after regenerating, never on return.
  defp load_section(socket, :credentials, uri) do
    socket
    |> assign(:secret, nil)
    |> assign(:curl_example, curl_example(uri, socket.assigns.app.slug))
  end

  defp load_section(socket, :origins, _uri) do
    socket
    |> assign(:env_origins, Origins.env_origins())
    |> assign(:origin_checks_off?, not Origins.checks_enabled?())
    |> assign_origin_form(Origins.change_allowed_origin(%AllowedOrigin{}))
    |> stream(:origins, Origins.list_allowed_origins(socket.assigns.app), reset: true)
  end

  defp load_section(socket, :chat, _uri) do
    rooms = Rooms.list_app_rooms(socket.assigns.app)

    socket
    |> assign(:rooms_count, length(rooms))
    |> assign(:room_form, to_form(Rooms.change_room(%{type: "group"})))
    |> stream(:rooms, rooms, reset: true)
  end

  defp load_section(socket, :settings, _uri), do: socket

  @impl true
  def handle_event(_event, _params, %{assigns: %{superadmin?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "Only the superadmin can do that.")}
  end

  def handle_event("validate_topic", %{"topic" => params}, socket) do
    {:noreply, assign(socket, :topic_form, topic_form(params, topic_errors(socket, params)))}
  end

  def handle_event("create_topic", %{"topic" => params}, socket) do
    app = socket.assigns.app

    with [] <- topic_errors(socket, params),
         {:ok, topic} <- Topics.create_topic(app, %{name: topic_name(socket, params["name"])}) do
      {:noreply,
       socket
       |> put_flash(:info, "Created #{topic.name}.")
       |> assign(:topic_form, topic_form(%{"name" => ""}))
       |> load_topic_level()}
    else
      errors when is_list(errors) ->
        {:noreply, assign(socket, :topic_form, topic_form(params, errors))}

      {:error, changeset} ->
        {:noreply, assign(socket, :topic_form, topic_form(params, changeset.errors))}
    end
  end

  def handle_event("validate_room", %{"room" => params}, socket) do
    changeset = params |> Rooms.change_room() |> Map.put(:action, :validate)
    {:noreply, assign(socket, :room_form, to_form(changeset))}
  end

  def handle_event("create_room", %{"room" => params}, socket) do
    app = socket.assigns.app

    case Rooms.create_room(app, params) do
      {:ok, room, events} ->
        Broadcast.dispatch(app, events)

        {:noreply,
         socket
         |> put_flash(:info, "Created #{room.name}.")
         |> assign(:room_form, to_form(Rooms.change_room(%{type: room.type})))
         |> assign(:rooms_count, socket.assigns.rooms_count + 1)
         |> stream_insert(:rooms, %{room | members_count: 0}, at: 0)}

      {:error, changeset} ->
        {:noreply, assign(socket, :room_form, to_form(changeset))}
    end
  end

  def handle_event("regenerate_secret", _params, socket) do
    {:ok, app} = Applications.regenerate_secret(socket.assigns.app)
    {:noreply, socket |> assign(:app, %{app | secret: nil}) |> assign(:secret, app.secret)}
  end

  def handle_event("validate_origin", %{"allowed_origin" => params}, socket) do
    changeset = Origins.change_allowed_origin(%AllowedOrigin{}, params)
    {:noreply, assign_origin_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("add_origin", %{"allowed_origin" => params}, socket) do
    case Origins.create_allowed_origin(socket.assigns.app, params) do
      {:ok, allowed_origin} ->
        {:noreply,
         socket
         |> put_flash(
           :info,
           "#{allowed_origin.origin} can now listen to #{socket.assigns.app.slug}."
         )
         |> stream_insert(:origins, allowed_origin)
         |> assign_origin_form(Origins.change_allowed_origin(%AllowedOrigin{}))}

      {:error, changeset} ->
        {:noreply, assign_origin_form(socket, changeset)}
    end
  end

  def handle_event("remove_origin", %{"id" => id}, socket) do
    case Origins.delete_allowed_origin(socket.assigns.app, id) do
      {:ok, allowed_origin} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{allowed_origin.origin} removed.")
         |> stream_delete(:origins, allowed_origin)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_app", _params, socket) do
    chat_user_ids = Users.list_user_ids(socket.assigns.app)
    {:ok, app} = Applications.delete_app(socket.assigns.app)

    # Their tokens already stop working; this closes sockets that are open.
    for id <- chat_user_ids,
        do: EventbusWeb.Endpoint.broadcast("chat_socket:#{id}", "disconnect", %{})

    {:noreply,
     socket
     |> put_flash(:info, "Deleted #{app.slug} and its topics.")
     |> push_navigate(to: ~p"/apps")}
  end

  defp assign_origin_form(socket, changeset), do: assign(socket, :origin_form, to_form(changeset))

  # The current level of the topic tree: its groups as a plain list (there
  # are few), its topics as a stream (there can be many).
  defp load_topic_level(socket) do
    %{groups: groups, topics: topics} =
      Topics.list_app_topic_level(socket.assigns.app, socket.assigns.topic_group)

    socket
    |> assign(:topic_groups, groups)
    |> assign(:topics_count, length(topics))
    |> stream(:topics, topics, reset: true)
  end

  # The topic form only takes the part of the name after "<slug>.<group>.",
  # so it's a plain params form with errors computed here.
  defp topic_form(params, errors \\ []), do: to_form(params, as: "topic", errors: errors)

  defp topic_errors(socket, params) do
    app = socket.assigns.app

    case String.trim(params["name"] || "") do
      "" -> [name: {"can't be blank", []}]
      name -> Topics.change_topic(app, %{name: topic_name(socket, name)}).errors
    end
  end

  defp topic_name(socket, name) do
    %{app: app, topic_group: group} = socket.assigns
    topic_prefix(app, group) <> String.trim(name || "")
  end

  defp topic_prefix(app, ""), do: "#{app.slug}."
  defp topic_prefix(app, group), do: "#{app.slug}.#{group}."

  # One breadcrumb per segment of `group`: {segment, group path up to it}.
  defp group_crumbs(group) do
    group
    |> String.split(".", trim: true)
    |> Enum.scan({nil, ""}, fn segment, {_, path} ->
      {segment, if(path == "", do: segment, else: "#{path}.#{segment}")}
    end)
  end

  defp group_path(slug, ""), do: ~p"/apps/#{slug}/topics"
  defp group_path(slug, group), do: ~p"/apps/#{slug}/topics?#{[group: group]}"

  defp child_group("", segment), do: segment
  defp child_group(group, segment), do: "#{group}.#{segment}"

  # Build the quick-start URL from the address the browser is on, not the
  # endpoint config: PHX_HOST may be a LAN IP while the page is being viewed
  # through a domain behind a TLS proxy. Once connected, `uri` is the
  # browser's own location, so scheme, host and port all match.
  defp curl_example(uri, slug) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)

    endpoint = %URI{
      scheme: scheme,
      host: host,
      port: port,
      path: "/api/topics/#{slug}.my-topic/events"
    }

    """
    curl -u "$CLIENT_ID:$CLIENT_SECRET" \\
      -X POST #{URI.to_string(endpoint)} \\
      -H "Content-Type: application/json" \\
      -d '{"hello": "world"}'\
    """
  end

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y · %H:%M UTC")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:apps}>
      <.app_shell
        :if={@live_action != :index}
        app={@app}
        active={@live_action}
        superadmin?={@superadmin?}
      >
        <.topics_section
          :if={@live_action == :topics}
          app={@app}
          superadmin?={@superadmin?}
          topic_form={@topic_form}
          topic_group={@topic_group}
          topic_groups={@topic_groups}
          topics_count={@topics_count}
          topics={@streams.topics}
        />
        <.chat_section
          :if={@live_action == :chat}
          app={@app}
          superadmin?={@superadmin?}
          room_form={@room_form}
          rooms_count={@rooms_count}
          rooms={@streams.rooms}
        />
        <.credentials_section
          :if={@live_action == :credentials}
          app={@app}
          secret={@secret}
          curl_example={@curl_example}
        />
        <.origins_section
          :if={@live_action == :origins}
          app={@app}
          origin_form={@origin_form}
          origins={@streams.origins}
          env_origins={@env_origins}
          origin_checks_off?={@origin_checks_off?}
        />
        <.settings_section :if={@live_action == :settings} app={@app} />
      </.app_shell>
    </Layouts.app>
    """
  end

  attr :app, :any, required: true
  attr :superadmin?, :boolean, required: true
  attr :topic_form, :any, required: true
  attr :topic_group, :string, required: true
  attr :topic_groups, :list, required: true
  attr :topics_count, :integer, required: true
  attr :topics, :any, required: true

  defp topics_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <.card :if={@superadmin?} id="new-topic">
        <h2 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-plus-circle" class="size-5 text-primary" /> New topic
        </h2>
        <p class="mt-1 text-sm text-base-content/50">
          Publishing to a new name creates it too. Lowercase letters, digits,
          <code class="font-mono">.</code> <code class="font-mono">-</code>
          <code class="font-mono">_</code>
        </p>
        <.form
          for={@topic_form}
          id="topic-form"
          phx-change="validate_topic"
          phx-submit="create_topic"
          class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-start"
        >
          <div class="flex min-w-0 flex-1 items-start">
            <span class="mt-1 flex h-10 items-center rounded-l-lg border border-r-0 border-base-content/20 bg-base-content/5 px-3 font-mono text-sm text-base-content/60">
              {topic_prefix(@app, @topic_group)}
            </span>
            <div class="min-w-0 flex-1 [&_input]:rounded-l-none">
              <.input
                field={@topic_form[:name]}
                placeholder="logs"
                autocomplete="off"
                phx-debounce="300"
              />
            </div>
          </div>
          <%!-- The zone overhangs the button so the pull starts just before
               the cursor reaches it. JS-set offsets live in inline styles,
               so LiveView must leave this subtree alone. --%>
          <div
            id="create-topic-zone"
            phx-hook=".Magnetic"
            phx-update="ignore"
            class="mag-zone -m-3 p-3 sm:w-48"
          >
            <button
              id="create-topic"
              type="submit"
              class="mag-btn mt-1 w-full rounded-full px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 phx-submit-loading:opacity-60"
            >
              <span class="mag-label inline-flex items-center gap-2">
                <.icon name="hero-plus" class="size-4" /> Create topic
              </span>
            </button>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".Magnetic">
            // Magnetic button, after GreenSock's "Dynamic tweens" pen: the
            // button leans toward the cursor and its label leans a little
            // further; easing and the elastic snap-back are in app.css.
            export default {
              mounted() {
                if (!matchMedia("(pointer: fine)").matches) return
                if (matchMedia("(prefers-reduced-motion: reduce)").matches) return

                const zone = this.el
                const btn = zone.querySelector(".mag-btn")
                const label = zone.querySelector(".mag-label")
                const offset = (el, x, y) => {
                  el.style.setProperty("--mag-x", `${x}px`)
                  el.style.setProperty("--mag-y", `${y}px`)
                }

                this.onMove = e => {
                  const r = zone.getBoundingClientRect()
                  const x = e.clientX - (r.left + r.width / 2)
                  const y = e.clientY - (r.top + r.height / 2)
                  zone.classList.add("is-pulled")
                  // The button is wide, so pull less on x than on y.
                  offset(btn, x * 0.1, y * 0.35)
                  offset(label, x * 0.06, y * 0.2)
                }
                this.onLeave = () => {
                  zone.classList.remove("is-pulled")
                  offset(btn, 0, 0)
                  offset(label, 0, 0)
                }
                zone.addEventListener("pointermove", this.onMove)
                zone.addEventListener("pointerleave", this.onLeave)
              },
              destroyed() {
                this.el.removeEventListener("pointermove", this.onMove)
                this.el.removeEventListener("pointerleave", this.onLeave)
              }
            }
          </script>
        </.form>
      </.card>

      <div>
        <div class="mb-3 flex items-baseline justify-between gap-4">
          <nav
            id="topic-crumbs"
            aria-label="Topic groups"
            class="flex min-w-0 flex-wrap items-center gap-1 text-sm font-semibold uppercase tracking-wider text-base-content/50"
          >
            <.link
              patch={group_path(@app.slug, "")}
              class={[
                "transition-colors hover:text-primary",
                @topic_group == "" && "text-base-content/80"
              ]}
            >
              Topics
            </.link>
            <%= for {segment, path} <- group_crumbs(@topic_group) do %>
              <.icon name="hero-chevron-right-mini" class="size-4 shrink-0 text-base-content/30" />
              <.link
                patch={group_path(@app.slug, path)}
                class={[
                  "truncate font-mono normal-case tracking-normal transition-colors hover:text-primary",
                  path == @topic_group && "text-base-content/80"
                ]}
              >
                {segment}
              </.link>
            <% end %>
          </nav>
          <span id="topics-count" class="shrink-0 text-sm tabular-nums text-base-content/50">
            <span :if={@topic_groups != []}>
              {length(@topic_groups)} {if length(@topic_groups) == 1, do: "group", else: "groups"} ·
            </span>
            {@topics_count} {if @topics_count == 1, do: "topic", else: "topics"}
          </span>
        </div>
        <ul :if={@topic_groups != []} id="topic-groups" class="mb-3 grid gap-3 sm:grid-cols-2">
          <li :for={{segment, count} <- @topic_groups} id={"topic-group-#{segment}"}>
            <.link
              patch={group_path(@app.slug, child_group(@topic_group, segment))}
              class="group flex h-full items-center gap-4 rounded-2xl border border-base-content/10 bg-base-200/40 p-4 transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/40 hover:bg-base-100 hover:shadow-md hover:shadow-primary/5"
            >
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-base-content/5 text-base-content/60 transition-colors group-hover:bg-primary/10 group-hover:text-primary">
                <.icon name="hero-folder" class="size-5" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate font-mono text-sm font-medium">
                  <span class="text-base-content/40">{topic_prefix(@app, @topic_group)}</span>{segment}
                </span>
                <span class="mt-0.5 block text-xs text-base-content/50">
                  {count} {if count == 1, do: "topic", else: "topics"}
                </span>
              </span>
              <.icon
                name="hero-chevron-right"
                class="size-4 shrink-0 text-base-content/30 transition-all group-hover:translate-x-0.5 group-hover:text-primary"
              />
            </.link>
          </li>
        </ul>
        <ul id="topics" phx-update="stream" class="grid gap-3 sm:grid-cols-2">
          <li
            :if={@topic_groups == []}
            id="topics-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/10 px-4 py-5 text-sm text-base-content/50 sm:col-span-2"
          >
            No topics yet. Publish to
            <code class="font-mono">{topic_prefix(@app, @topic_group)}&lt;name&gt;</code>
            with this app's credentials to create one.
          </li>
          <li :for={{id, topic} <- @topics} id={id}>
            <.link
              navigate={~p"/apps/#{@app.slug}/topics/#{topic.name}"}
              class="group flex h-full items-center gap-4 rounded-2xl border border-base-content/10 bg-base-100 p-4 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md hover:shadow-primary/5"
            >
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary transition-colors group-hover:bg-primary group-hover:text-primary-content">
                <.icon name="hero-signal" class="size-5" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate font-mono text-sm font-medium">
                  <span class="text-base-content/40">{topic_prefix(@app, @topic_group)}</span>{String.replace_prefix(
                    topic.name,
                    topic_prefix(@app, @topic_group),
                    ""
                  )}
                </span>
                <span class="mt-0.5 block text-xs text-base-content/50">
                  Created {format_date(topic.inserted_at)}
                </span>
              </span>
              <.icon
                name="hero-arrow-right"
                class="size-4 shrink-0 text-base-content/30 transition-all group-hover:translate-x-0.5 group-hover:text-primary"
              />
            </.link>
          </li>
        </ul>
        <p class="mt-4 text-sm text-base-content/50">
          Listen by joining <code class="font-mono text-base-content/80">topic:&lt;name&gt;</code>
          on the <code class="font-mono text-base-content/80">/socket</code>
          WebSocket. Browser pages need their site under Origins.
        </p>
      </div>
    </div>
    """
  end

  attr :app, :any, required: true
  attr :superadmin?, :boolean, required: true
  attr :room_form, :any, required: true
  attr :rooms_count, :integer, required: true
  attr :rooms, :any, required: true

  defp chat_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <.card :if={@superadmin?} id="new-room">
        <h2 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-plus-circle" class="size-5 text-primary" /> New room
        </h2>
        <p class="mt-1 text-sm text-base-content/50">
          Group rooms are for their members only; any of {@app.slug}'s chat users can join a public room.
          Direct rooms are created through the API.
        </p>
        <.form
          for={@room_form}
          id="room-form"
          phx-change="validate_room"
          phx-submit="create_room"
          class="mt-4 flex flex-col gap-2 sm:flex-row sm:items-start"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@room_form[:name]}
              placeholder="engineering"
              autocomplete="off"
              phx-debounce="300"
            />
          </div>
          <div class="sm:w-36">
            <.input
              field={@room_form[:type]}
              type="select"
              options={[{"Group", "group"}, {"Public", "public"}]}
            />
          </div>
          <button
            id="create-room"
            type="submit"
            class="mt-1 inline-flex shrink-0 items-center justify-center gap-1.5 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
          >
            <.icon name="hero-plus" class="size-4" /> Create room
          </button>
        </.form>
      </.card>

      <div>
        <div class="mb-3 flex items-baseline justify-between">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
            Rooms
          </h2>
          <span id="rooms-count" class="text-sm tabular-nums text-base-content/50">
            {@rooms_count} {if @rooms_count == 1, do: "room", else: "rooms"}
          </span>
        </div>
        <ul id="rooms" phx-update="stream" class="grid gap-3 sm:grid-cols-2">
          <li
            id="rooms-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/10 px-4 py-5 text-sm text-base-content/50 sm:col-span-2"
          >
            No rooms yet. Create one here, or with <code class="font-mono">POST /api/chat/rooms</code>.
          </li>
          <li :for={{id, room} <- @rooms} id={id}>
            <.link
              navigate={~p"/apps/#{@app.slug}/chat/rooms/#{room.id}"}
              class="group flex h-full items-center gap-4 rounded-2xl border border-base-content/10 bg-base-100 p-4 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md hover:shadow-primary/5"
            >
              <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary transition-colors group-hover:bg-primary group-hover:text-primary-content">
                <.icon name={room_icon(room.type)} class="size-5" />
              </span>
              <span class="min-w-0 flex-1">
                <span class="block truncate text-sm font-medium">{room_label(room)}</span>
                <span class="mt-0.5 block text-xs text-base-content/50">
                  {String.capitalize(room.type)} · {room.members_count} {if room.members_count == 1,
                    do: "member",
                    else: "members"}
                  <%= if room.last_message_at do %>
                    · active {format_date(room.last_message_at)}
                  <% end %>
                </span>
              </span>
              <.icon
                name="hero-arrow-right"
                class="size-4 shrink-0 text-base-content/30 transition-all group-hover:translate-x-0.5 group-hover:text-primary"
              />
            </.link>
          </li>
        </ul>
        <.link
          :if={@superadmin?}
          id="open-chat-demo"
          navigate={~p"/apps/#{@app.slug}/chat/demo"}
          class="mt-4 inline-flex items-center gap-1.5 rounded-full border border-primary/30 px-4 py-2 text-sm font-medium text-primary transition-colors hover:bg-primary/5"
        >
          <.icon name="hero-play-micro" class="size-4" /> Try it in the demo
        </.link>
        <p class="mt-4 text-sm text-base-content/50">
          Chat users connect to <code class="font-mono text-base-content/80">/socket</code>
          with a token from <code class="font-mono text-base-content/80">POST /api/chat/tokens</code>
          and join <code class="font-mono text-base-content/80">chat:{@app.slug}:&lt;room id&gt;</code>.
        </p>
      </div>
    </div>
    """
  end

  attr :app, :any, required: true
  attr :secret, :string, required: true
  attr :curl_example, :string, required: true

  defp credentials_section(assigns) do
    ~H"""
    <div class="space-y-6">
      <.card id="credentials">
        <h2 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-key" class="size-5 text-primary" /> Credentials
        </h2>
        <p class="mt-1 text-sm text-base-content/50">
          Publish to <code class="font-mono">{@app.slug}.*</code>
          with HTTP Basic auth: the client ID as user, the secret as password.
        </p>
        <div class="mt-5 space-y-3">
          <.credential_row id="credentials-client-id" label="Client ID" value={@app.client_id} />
          <%= if @secret do %>
            <.credential_row id="credentials-secret" label="Secret" value={@secret} secret />
            <p class="flex gap-2 text-xs text-base-content/70">
              <.icon name="hero-exclamation-triangle-micro" class="size-4 shrink-0 text-warning" />
              Store this secret now. It won't be shown again.
            </p>
          <% else %>
            <p class="text-xs text-base-content/50">
              The secret was shown once, when it was created. Lost it? Regenerate it.
            </p>
            <button
              id="regenerate-secret"
              type="button"
              phx-click={
                JS.hide()
                |> JS.show(to: "#regenerate-confirm", display: "flex", transition: confirm_in())
              }
              class="inline-flex items-center gap-1.5 rounded-full border border-base-content/15 px-3 py-1.5 text-xs font-medium transition-colors hover:bg-base-content/5"
            >
              <.icon name="hero-arrow-path-micro" class="size-4" /> Regenerate secret
            </button>
            <div
              id="regenerate-confirm"
              class="hidden flex-col gap-2 rounded-xl bg-error/10 p-3 text-xs"
            >
              <p class="text-base-content/80">
                The current secret stops working immediately. Publishers using it will get 401 until updated.
              </p>
              <div class="flex gap-2">
                <button
                  id="regenerate-cancel"
                  type="button"
                  phx-click={JS.hide(to: "#regenerate-confirm") |> JS.show(to: "#regenerate-secret")}
                  class="rounded-md px-2 py-1 font-medium text-base-content/70 transition-colors hover:bg-base-content/5"
                >
                  Cancel
                </button>
                <button
                  id="regenerate-confirm-button"
                  type="button"
                  phx-click="regenerate_secret"
                  phx-disable-with="Regenerating…"
                  class="rounded-md bg-error px-2.5 py-1 font-semibold text-error-content shadow-sm transition-all hover:brightness-110 active:scale-95"
                >
                  Regenerate
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </.card>

      <.card id="quick-start">
        <h2 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-command-line" class="size-5 text-primary" /> Quick start
        </h2>
        <pre
          id="curl-example"
          class="mt-3 whitespace-pre-wrap break-all rounded-lg bg-neutral p-3 font-mono text-xs leading-relaxed text-neutral-content"
        >{@curl_example}</pre>
      </.card>
    </div>
    """
  end

  attr :app, :any, required: true
  attr :origin_form, :any, required: true
  attr :origins, :any, required: true
  attr :env_origins, :list, required: true
  attr :origin_checks_off?, :boolean, required: true

  defp origins_section(assigns) do
    ~H"""
    <.card id="allowed-origins">
      <h2 class="flex items-center gap-2 font-semibold">
        <.icon name="hero-globe-alt" class="size-5 text-primary" /> Allowed origins
      </h2>
      <p class="mt-1 text-sm text-base-content/50">
        Web pages on these origins can listen to
        <code class="font-mono text-base-content/80">{@app.slug}.*</code>
        over the <code class="font-mono text-base-content/80">/socket</code>
        WebSocket, and nothing else. Server-side clients don't send an origin and aren't affected.
        Changes apply to new joins immediately.
      </p>

      <div
        :if={@origin_checks_off?}
        id="origin-checks-off"
        class="mt-4 flex gap-2 rounded-xl bg-warning/10 px-3 py-2.5 text-sm text-base-content/80"
      >
        <.icon name="hero-exclamation-triangle" class="size-5 shrink-0 text-warning" />
        Origin checks are turned off in this environment, so every origin can connect. This list only takes effect in production.
      </div>

      <.form
        for={@origin_form}
        id="origin-form"
        phx-change="validate_origin"
        phx-submit="add_origin"
        class="mt-5 flex items-start gap-2"
      >
        <div class="min-w-0 flex-1">
          <.input
            field={@origin_form[:origin]}
            placeholder={"https://#{@app.slug}.com"}
            autocomplete="off"
            phx-debounce="300"
          />
        </div>
        <button
          id="add-origin"
          type="submit"
          class="mt-1 inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
        >
          <.icon name="hero-plus-micro" class="size-4" /> Add
        </button>
      </.form>
      <p class="mt-1 text-xs text-base-content/50">
        <code class="font-mono">example.com</code>
        any scheme and port · <code class="font-mono">https://example.com</code>
        exact · <code class="font-mono">localhost:5173</code>
        one port · <code class="font-mono">*.example.com</code>
        subdomains
      </p>

      <h3 class="mt-6 mb-2 text-xs font-semibold uppercase tracking-wider text-base-content/50">
        This app
      </h3>
      <ul id="origins" phx-update="stream" class="divide-y divide-base-content/5">
        <li id="origins-empty" class="hidden py-3 text-sm text-base-content/50 only:block">
          No origins yet. Only the ones below can listen from a browser.
        </li>
        <li
          :for={{id, allowed_origin} <- @origins}
          id={id}
          class="group flex items-center gap-3 py-2.5"
        >
          <.icon name="hero-link" class="size-4 shrink-0 text-base-content/40" />
          <span class="min-w-0 flex-1 truncate font-mono text-sm">{allowed_origin.origin}</span>
          <button
            id={"#{id}-remove"}
            type="button"
            phx-click="remove_origin"
            phx-value-id={allowed_origin.id}
            class="rounded-md p-1.5 text-base-content/30 transition-colors hover:bg-error/10 hover:text-error"
            aria-label={"Remove #{allowed_origin.origin}"}
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </li>
      </ul>

      <%= if @env_origins != [] do %>
        <h3 class="mt-6 mb-2 text-xs font-semibold uppercase tracking-wider text-base-content/50">
          Always allowed
        </h3>
        <ul id="env-origins" class="divide-y divide-base-content/5">
          <li
            :for={origin <- @env_origins}
            id={"env-origin-#{origin}"}
            class="flex items-center gap-3 py-2.5"
          >
            <.icon name="hero-lock-closed" class="size-4 shrink-0 text-base-content/40" />
            <span class="min-w-0 flex-1 truncate font-mono text-sm text-base-content/70">
              {origin}
            </span>
            <span class="rounded-full bg-base-content/5 px-2 py-0.5 text-xs text-base-content/50">
              PHX_HOST / PHX_EXTRA_ORIGINS
            </span>
          </li>
        </ul>
        <p class="mt-2 text-xs text-base-content/50">
          These come from the server's environment and may listen to every app.
          Change them in its environment variables.
        </p>
      <% end %>
    </.card>
    """
  end

  attr :app, :any, required: true

  defp settings_section(assigns) do
    ~H"""
    <.card id="danger-zone" class="border-error/30">
      <h2 class="flex items-center gap-2 font-semibold text-error">
        <.icon name="hero-exclamation-triangle" class="size-5" /> Danger zone
      </h2>
      <div class="mt-4 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <p class="font-medium">Delete this application</p>
          <p class="text-sm text-base-content/50">
            Deletes its topics, origins and chat. Its credentials and chat tokens stop working immediately.
          </p>
        </div>
        <button
          id="delete-app"
          type="button"
          phx-click={
            JS.hide()
            |> JS.show(to: "#delete-confirm", display: "flex", transition: confirm_in())
          }
          class="inline-flex shrink-0 items-center gap-1.5 rounded-full border border-error/40 px-4 py-2 text-sm font-semibold text-error transition-colors hover:bg-error/10"
        >
          <.icon name="hero-trash-micro" class="size-4" /> Delete app
        </button>
        <div id="delete-confirm" class="hidden shrink-0 items-center gap-2 text-sm">
          <span class="text-base-content/60">Delete {@app.slug}?</span>
          <button
            id="delete-cancel"
            type="button"
            phx-click={JS.hide(to: "#delete-confirm") |> JS.show(to: "#delete-app")}
            class="rounded-md px-2 py-1 font-medium text-base-content/70 transition-colors hover:bg-base-content/5"
          >
            Cancel
          </button>
          <button
            id="delete-confirm-button"
            type="button"
            phx-click="delete_app"
            phx-disable-with="Deleting…"
            class="rounded-md bg-error px-3 py-1 font-semibold text-error-content shadow-sm transition-all hover:brightness-110 active:scale-95"
          >
            Delete
          </button>
        </div>
      </div>
    </.card>
    """
  end
end
