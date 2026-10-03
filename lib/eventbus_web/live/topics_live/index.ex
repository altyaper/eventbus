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
     |> stream_configure(:groups, dom_id: &group_dom_id/1)
     |> assign_groups()}
  end

  # A new topic can start a new app group, which has to land in sorted order,
  # so re-read and reset the stream rather than inserting into it.
  defp assign_groups(socket) do
    groups = Topics.list_topics_by_app()

    socket
    |> assign(:topics_count, groups |> Enum.map(&length(&1.topics)) |> Enum.sum())
    |> stream(:groups, groups, reset: true)
  end

  defp group_dom_id(%{app: nil}), do: "ungrouped-topics"
  defp group_dom_id(%{app: app}), do: "app-#{app}"

  # Build the quick-start URL from the address the browser is on, not the
  # endpoint config: PHX_HOST may be a LAN IP while the page is being viewed
  # through a domain behind a TLS proxy. Once connected, `uri` is the
  # browser's own location, so scheme, host and port all match.
  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :curl_example, curl_example(uri))}
  end

  @impl true
  def handle_event("validate", %{"topic" => topic_params}, socket) do
    changeset = Topics.change_topic(%Topic{}, topic_params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("create", %{"topic" => topic_params}, socket) do
    case Topics.create_topic(topic_params) do
      {:ok, _topic} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Topics.change_topic(%Topic{})))
         |> assign_groups()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp curl_example(uri) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(uri)
    endpoint = %URI{scheme: scheme, host: host, port: port, path: "/api/topics/my.topic/events"}

    """
    curl -X POST #{URI.to_string(endpoint)} \\
      -H "Authorization: Bearer $EVENTBUS_API_KEY" \\
      -H "Content-Type: application/json" \\
      -d '{"hello": "world"}'\
    """
  end

  defp format_date(datetime), do: Calendar.strftime(datetime, "%b %-d, %Y · %H:%M UTC")

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
          Topics
        </h1>
        <p class="mt-2 max-w-xl text-base-content/60">
          Publish JSON events to a topic and every listener receives them instantly.
          Pick a topic to watch its stream live.
        </p>
      </section>

      <div class="grid gap-8 lg:grid-cols-3">
        <section class="lg:col-span-2">
          <div class="mb-4 flex items-baseline justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              All topics
            </h2>
            <span id="topics-count" class="text-sm tabular-nums text-base-content/50">
              {@topics_count} {if @topics_count == 1, do: "topic", else: "topics"}
            </span>
          </div>

          <div id="topics" phx-update="stream" class="space-y-8">
            <div
              id="topics-empty"
              class="hidden only:flex flex-col items-center rounded-2xl border border-dashed border-base-content/15 px-6 py-14 text-center"
            >
              <span class="grid size-12 place-items-center rounded-full bg-base-content/5">
                <.icon name="hero-inbox-stack" class="size-6 text-base-content/40" />
              </span>
              <p class="mt-4 font-medium">No topics yet</p>
              <p class="mt-1 text-sm text-base-content/50">
                Create one on the right, or just publish to a new name — it's created on first use.
              </p>
            </div>
            <section :for={{id, group} <- @streams.groups} id={id}>
              <h3 class="mb-3 flex items-center gap-2 text-sm font-semibold">
                <.icon
                  name={if group.app, do: "hero-cube", else: "hero-squares-2x2"}
                  class="size-4 text-base-content/40"
                />
                <span class={[group.app && "font-mono", !group.app && "text-base-content/60"]}>
                  {group.app || "Ungrouped"}
                </span>
                <span class="rounded-full bg-base-content/5 px-2 py-0.5 text-xs font-medium tabular-nums text-base-content/50">
                  {length(group.topics)}
                </span>
              </h3>
              <ul class="grid gap-3 sm:grid-cols-2">
                <li :for={topic <- group.topics} id={"topic-#{topic.id}"}>
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
          <div class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm">
            <h2 class="flex items-center gap-2 font-semibold">
              <.icon name="hero-plus-circle" class="size-5 text-primary" /> New topic
            </h2>
            <p class="mt-1 text-sm text-base-content/50">
              Lowercase letters, digits, <code class="font-mono">.</code>
              <code class="font-mono">-</code>
              <code class="font-mono">_</code>
              — the part before the first <code class="font-mono">.</code>
              groups it under an app.
            </p>
            <.form
              for={@form}
              id="topic-form"
              phx-change="validate"
              phx-submit="create"
              class="mt-4"
            >
              <.input
                field={@form[:name]}
                placeholder="changologs.logs"
                autocomplete="off"
                phx-debounce="300"
              />
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
              Publish over HTTP with your API key:
            </p>
            <pre
              id="curl-example"
              class="mt-3 whitespace-pre-wrap break-all rounded-lg bg-neutral p-3 font-mono text-xs leading-relaxed text-neutral-content"
            >{@curl_example}</pre>
            <p class="mt-3 text-sm text-base-content/50">
              Or join <code class="font-mono text-base-content/80">topic:&lt;name&gt;</code>
              on the <code class="font-mono text-base-content/80">/socket</code>
              WebSocket to listen and publish.
            </p>
          </div>
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
