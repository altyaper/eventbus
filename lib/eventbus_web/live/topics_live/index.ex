defmodule EventbusWeb.TopicsLive.Index do
  @moduledoc """
  The home page: applications with their topics nested under them. The
  superadmin creates and deletes applications, manages their credentials and
  creates topics; everyone else browses.
  """

  use EventbusWeb, :live_view

  alias Eventbus.{Applications, Topics}
  alias Eventbus.Accounts.Scope
  alias Eventbus.Applications.App

  @superadmin_events ~w(validate_app create_app validate_topic create_topic show_credentials
                        regenerate_secret delete_app)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Applications")
     |> assign(:superadmin?, Scope.superadmin?(socket.assigns.current_scope))
     |> assign(:credentials, nil)
     |> assign(:app_form, to_form(Applications.change_app(%App{})))
     |> assign(:topic_form, topic_form(%{"application_id" => "", "name" => ""}))
     |> stream_configure(:apps, dom_id: &"app-#{&1.slug}")
     |> assign_apps()}
  end

  # Apps are sorted by slug and carry their topics, so any change re-reads
  # them and resets the stream rather than patching it.
  defp assign_apps(socket) do
    apps = Applications.list_apps_with_topics()

    socket
    |> assign(:app_choices, Enum.map(apps, &{&1.slug, &1.id}))
    |> assign(:topics_count, apps |> Enum.map(&length(&1.topics)) |> Enum.sum())
    |> stream(:apps, apps, reset: true)
  end

  # Build the quick-start URL from the address the browser is on, not the
  # endpoint config: PHX_HOST may be a LAN IP while the page is being viewed
  # through a domain behind a TLS proxy. Once connected, `uri` is the
  # browser's own location, so scheme, host and port all match.
  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :curl_example, curl_example(uri))}
  end

  @impl true
  def handle_event(event, _params, %{assigns: %{superadmin?: false}} = socket)
      when event in @superadmin_events do
    {:noreply, put_flash(socket, :error, "Only the superadmin can do that.")}
  end

  def handle_event("validate_app", %{"app" => params}, socket) do
    changeset = Applications.change_app(%App{}, params)
    {:noreply, assign(socket, :app_form, to_form(changeset, action: :validate))}
  end

  def handle_event("create_app", %{"app" => params}, socket) do
    case Applications.create_app(params) do
      {:ok, app} ->
        {:noreply,
         socket
         |> assign(:app_form, to_form(Applications.change_app(%App{})))
         |> assign(:credentials, %{app: app, secret: app.secret})
         |> assign_apps()}

      {:error, changeset} ->
        {:noreply, assign(socket, :app_form, to_form(changeset))}
    end
  end

  def handle_event("validate_topic", %{"topic" => params}, socket) do
    {:noreply, assign(socket, :topic_form, topic_form(params, topic_errors(socket, params)))}
  end

  def handle_event("create_topic", %{"topic" => params}, socket) do
    with [] <- topic_errors(socket, params),
         app = Applications.get_app!(params["application_id"]),
         {:ok, topic} <- Topics.create_topic(app, %{name: full_name(app.slug, params["name"])}) do
      {:noreply,
       socket
       |> put_flash(:info, "Created #{topic.name}.")
       |> assign(
         :topic_form,
         topic_form(%{"application_id" => params["application_id"], "name" => ""})
       )
       |> assign_apps()}
    else
      errors when is_list(errors) ->
        {:noreply, assign(socket, :topic_form, topic_form(params, errors))}

      {:error, changeset} ->
        {:noreply, assign(socket, :topic_form, topic_form(params, changeset.errors))}
    end
  end

  def handle_event("show_credentials", %{"id" => id}, socket) do
    {:noreply, assign(socket, :credentials, %{app: Applications.get_app!(id), secret: nil})}
  end

  def handle_event("regenerate_secret", _params, socket) do
    {:ok, app} = Applications.regenerate_secret(socket.assigns.credentials.app)
    {:noreply, assign(socket, :credentials, %{app: app, secret: app.secret})}
  end

  def handle_event("dismiss_credentials", _params, socket) do
    {:noreply, assign(socket, :credentials, nil)}
  end

  def handle_event("delete_app", %{"id" => id}, socket) do
    app = Applications.get_app!(id)
    {:ok, _app} = Applications.delete_app(app)

    credentials =
      if socket.assigns.credentials && socket.assigns.credentials.app.id == app.id,
        do: nil,
        else: socket.assigns.credentials

    {:noreply,
     socket
     |> put_flash(:info, "Deleted #{app.slug} and its topics.")
     |> assign(:credentials, credentials)
     |> assign_apps()}
  end

  # The topic form takes an app and the part of the name after "<slug>.",
  # so it's a plain params form with errors computed here.
  defp topic_form(params, errors \\ []), do: to_form(params, as: "topic", errors: errors)

  defp topic_errors(socket, params) do
    slug = selected_slug(socket.assigns.app_choices, params["application_id"])
    name = String.trim(params["name"] || "")

    cond do
      is_nil(slug) ->
        [application_id: {"choose an application", []}]

      name == "" ->
        [name: {"can't be blank", []}]

      true ->
        app = %App{id: String.to_integer(params["application_id"]), slug: slug}
        Topics.change_topic(app, %{name: full_name(slug, name)}).errors
    end
  end

  defp selected_slug(app_choices, id) do
    Enum.find_value(app_choices, fn {slug, app_id} -> to_string(app_id) == id && slug end)
  end

  defp full_name(slug, name), do: "#{slug}.#{String.trim(name || "")}"

  defp curl_example(uri) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)

    endpoint = %URI{
      scheme: scheme,
      host: host,
      port: port,
      path: "/api/topics/my-app.my-topic/events"
    }

    """
    curl -u "$CLIENT_ID:$CLIENT_SECRET" \\
      -X POST #{URI.to_string(endpoint)} \\
      -H "Content-Type: application/json" \\
      -d '{"hello": "world"}'\
    """
  end

  defp confirm_in,
    do: {"transition ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"}

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y · %H:%M UTC")

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :secret, :boolean, default: false

  defp credential_row(assigns) do
    ~H"""
    <div>
      <p class="text-xs font-medium text-base-content/60">{@label}</p>
      <div class={[
        "mt-1 flex items-center gap-2 rounded-lg px-3 py-2",
        if(@secret, do: "bg-warning/10 ring-1 ring-warning/30", else: "bg-base-content/5")
      ]}>
        <code id={@id} class="min-w-0 flex-1 break-all font-mono text-xs">{@value}</code>
        <button
          id={"#{@id}-copy"}
          type="button"
          phx-hook=".CopyText"
          data-copy-target={"##{@id}"}
          class="shrink-0 rounded-md p-1.5 text-base-content/60 transition-colors hover:bg-base-content/10 hover:text-base-content"
          aria-label={"Copy #{@label}"}
        >
          <.icon name="hero-clipboard-document" class="size-4 copy-idle" />
          <.icon name="hero-check" class="hidden size-4 text-success copy-done" />
        </button>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section id="hero" class="mb-10 sm:mb-14">
        <span class="inline-flex items-center gap-2 rounded-full border border-base-content/10 bg-base-100/60 px-3 py-1 text-xs font-medium text-base-content/70">
          <span class="relative flex size-2">
            <span class="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" />
            <span class="relative inline-flex size-2 rounded-full bg-success" />
          </span>
          Real-time pub/sub over HTTP &amp; WebSockets
        </span>
        <h1 class="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">
          Applications
        </h1>
        <p class="mt-2 max-w-xl text-base-content/60">
          Each application owns the topics under its name and publishes to them with its own
          credentials. Pick a topic to watch its stream live.
        </p>
      </section>

      <div class="grid gap-8 lg:grid-cols-3">
        <section class="lg:col-span-2">
          <div class="mb-4 flex items-baseline justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              All applications
            </h2>
            <span id="topics-count" class="text-sm tabular-nums text-base-content/50">
              {@topics_count} {if @topics_count == 1, do: "topic", else: "topics"}
            </span>
          </div>

          <div id="apps" phx-update="stream" class="space-y-8">
            <div
              id="apps-empty"
              class="hidden only:flex flex-col items-center rounded-2xl border border-dashed border-base-content/15 px-6 py-14 text-center"
            >
              <span class="grid size-12 place-items-center rounded-full bg-base-content/5">
                <.icon name="hero-cube-transparent" class="size-6 text-base-content/40" />
              </span>
              <p class="mt-4 font-medium">No applications yet</p>
              <p class="mt-1 text-sm text-base-content/50">
                Create your first application, then publish to its topics with its credentials.
              </p>
            </div>
            <section :for={{id, app} <- @streams.apps} id={id}>
              <h3 class="mb-3 flex items-center gap-2 text-sm font-semibold">
                <.icon name="hero-cube" class="size-4 text-base-content/40" />
                <span class="font-mono">{app.slug}</span>
                <span class="rounded-full bg-base-content/5 px-2 py-0.5 text-xs font-medium tabular-nums text-base-content/50">
                  {length(app.topics)}
                </span>
                <%= if @superadmin? do %>
                  <span id={"#{id}-actions"} class="ml-auto flex items-center gap-1">
                    <button
                      id={"#{id}-credentials"}
                      type="button"
                      phx-click="show_credentials"
                      phx-value-id={app.id}
                      class="flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-base-content/50 transition-colors hover:bg-base-content/5 hover:text-base-content"
                    >
                      <.icon name="hero-key" class="size-3.5" /> Credentials
                    </button>
                    <button
                      id={"#{id}-delete"}
                      type="button"
                      phx-click={
                        JS.hide(to: "##{id}-actions")
                        |> JS.show(to: "##{id}-confirm", display: "flex", transition: confirm_in())
                      }
                      class="rounded-md p-1.5 text-base-content/30 transition-colors hover:bg-error/10 hover:text-error"
                      aria-label={"Delete #{app.slug}"}
                    >
                      <.icon name="hero-trash" class="size-4" />
                    </button>
                  </span>
                  <span
                    id={"#{id}-confirm"}
                    class="ml-auto hidden items-center gap-2 text-xs font-normal"
                  >
                    <span class="text-base-content/60">
                      Delete {app.slug} and its {length(app.topics)} {if length(app.topics) == 1,
                        do: "topic",
                        else: "topics"}?
                    </span>
                    <button
                      id={"#{id}-cancel"}
                      type="button"
                      phx-click={
                        JS.hide(to: "##{id}-confirm")
                        |> JS.show(to: "##{id}-actions", display: "flex")
                      }
                      class="rounded-md px-2 py-1 font-medium text-base-content/70 transition-colors hover:bg-base-content/5"
                    >
                      Cancel
                    </button>
                    <button
                      id={"#{id}-confirm-delete"}
                      type="button"
                      phx-click="delete_app"
                      phx-value-id={app.id}
                      phx-disable-with="Deleting…"
                      class="rounded-md bg-error px-2.5 py-1 font-semibold text-error-content shadow-sm transition-all hover:brightness-110 active:scale-95"
                    >
                      Delete
                    </button>
                  </span>
                <% end %>
              </h3>
              <p
                :if={app.topics == []}
                class="rounded-2xl border border-dashed border-base-content/10 px-4 py-5 text-sm text-base-content/50"
              >
                No topics yet. Publish to <code class="font-mono">{app.slug}.&lt;name&gt;</code>
                with this app's credentials to create one.
              </p>
              <ul :if={app.topics != []} class="grid gap-3 sm:grid-cols-2">
                <li :for={topic <- app.topics} id={"topic-#{topic.id}"}>
                  <.link
                    navigate={~p"/topics/#{topic.name}"}
                    class="group flex h-full items-center gap-4 rounded-2xl border border-base-content/10 bg-base-100 p-4 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md hover:shadow-primary/5"
                  >
                    <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary transition-colors group-hover:bg-primary group-hover:text-primary-content">
                      <.icon name="hero-signal" class="size-5" />
                    </span>
                    <span class="min-w-0 flex-1">
                      <span class="block truncate font-mono text-sm font-medium">{topic.name}</span>
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
            </section>
          </div>
        </section>

        <aside class="space-y-6">
          <div
            :if={@credentials}
            id="credentials"
            class="rounded-2xl border border-primary/30 bg-base-100 p-5 shadow-lg shadow-primary/10 ring-1 ring-primary/20"
          >
            <div class="flex items-start justify-between gap-2">
              <h2 class="flex items-center gap-2 font-semibold">
                <.icon name="hero-key" class="size-5 text-primary" />
                <span><span class="font-mono">{@credentials.app.slug}</span> credentials</span>
              </h2>
              <button
                id="dismiss-credentials"
                type="button"
                phx-click="dismiss_credentials"
                class="rounded-md p-1 text-base-content/40 transition-colors hover:bg-base-content/5 hover:text-base-content"
                aria-label="Close"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <div class="mt-4 space-y-3">
              <.credential_row
                id="credentials-client-id"
                label="Client ID"
                value={@credentials.app.client_id}
              />
              <%= if @credentials.secret do %>
                <.credential_row
                  id="credentials-secret"
                  label="Secret"
                  value={@credentials.secret}
                  secret
                />
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
                      phx-click={
                        JS.hide(to: "#regenerate-confirm") |> JS.show(to: "#regenerate-secret")
                      }
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
            <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyText">
              export default {
                mounted() {
                  this.el.addEventListener("click", () => {
                    const text = document.querySelector(this.el.dataset.copyTarget).textContent.trim()
                    navigator.clipboard.writeText(text).then(() => {
                      this.el.querySelector(".copy-idle").classList.add("hidden")
                      this.el.querySelector(".copy-done").classList.remove("hidden")
                      clearTimeout(this.timer)
                      this.timer = setTimeout(() => {
                        this.el.querySelector(".copy-idle").classList.remove("hidden")
                        this.el.querySelector(".copy-done").classList.add("hidden")
                      }, 1500)
                    })
                  })
                }
              }
            </script>
          </div>

          <div
            :if={@superadmin?}
            class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm"
          >
            <h2 class="flex items-center gap-2 font-semibold">
              <.icon name="hero-cube" class="size-5 text-primary" /> New application
            </h2>
            <p class="mt-1 text-sm text-base-content/50">
              Its name prefixes every topic it owns. It can't be renamed later.
            </p>
            <.form
              for={@app_form}
              id="app-form"
              phx-change="validate_app"
              phx-submit="create_app"
              class="mt-4 flex items-start gap-2"
            >
              <div class="min-w-0 flex-1">
                <.input
                  field={@app_form[:slug]}
                  placeholder="changologs"
                  autocomplete="off"
                  phx-debounce="300"
                />
              </div>
              <button
                id="create-app"
                type="submit"
                class="mt-1 inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
              >
                <.icon name="hero-plus-micro" class="size-4" /> Create
              </button>
            </.form>
          </div>

          <div
            :if={@superadmin?}
            class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm"
          >
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
              class="mt-4"
            >
              <fieldset disabled={@app_choices == []} class="disabled:opacity-50">
                <.input
                  field={@topic_form[:application_id]}
                  type="select"
                  options={@app_choices}
                  prompt={
                    if @app_choices == [], do: "Create an application first", else: "Application"
                  }
                />
                <.input
                  field={@topic_form[:name]}
                  placeholder="logs"
                  autocomplete="off"
                  phx-debounce="300"
                />
                <p
                  :if={slug = selected_slug(@app_choices, @topic_form[:application_id].value)}
                  id="topic-full-name"
                  class="-mt-1 mb-2 truncate text-xs text-base-content/50"
                >
                  Full name:
                  <code class="font-mono text-base-content/80">{full_name(
                    slug,
                    @topic_form[:name].value
                  )}</code>
                </p>
                <%!-- The zone overhangs the button so the pull starts just before
                     the cursor reaches it. JS-set offsets live in inline styles,
                     so LiveView must leave this subtree alone. --%>
                <div
                  id="create-topic-zone"
                  phx-hook=".Magnetic"
                  phx-update="ignore"
                  class="mag-zone -mx-3 -mb-3 p-3 pt-1"
                >
                  <button
                    id="create-topic"
                    type="submit"
                    class="mag-btn w-full rounded-full px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 phx-submit-loading:opacity-60"
                  >
                    <span class="mag-label inline-flex items-center gap-2">
                      <.icon name="hero-plus" class="size-4" /> Create topic
                    </span>
                  </button>
                </div>
              </fieldset>
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
          </div>

          <div class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm">
            <h2 class="flex items-center gap-2 font-semibold">
              <.icon name="hero-command-line" class="size-5 text-primary" /> Quick start
            </h2>
            <p class="mt-1 text-sm text-base-content/50">
              Publish over HTTP with an application's client ID and secret:
            </p>
            <pre
              id="curl-example"
              class="mt-3 whitespace-pre-wrap break-all rounded-lg bg-neutral p-3 font-mono text-xs leading-relaxed text-neutral-content"
            >{@curl_example}</pre>
            <p class="mt-3 text-sm text-base-content/50">
              Listen by joining <code class="font-mono text-base-content/80">topic:&lt;name&gt;</code>
              on the <code class="font-mono text-base-content/80">/socket</code>
              WebSocket.
            </p>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
