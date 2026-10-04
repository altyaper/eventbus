defmodule EventbusWeb.AppsLive do
  @moduledoc """
  My Apps: a card per application the user owns, linking to its pages.
  Confirmed users create applications here and see the new secret once.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents

  alias Eventbus.Applications
  alias Eventbus.Accounts.Scope
  alias Eventbus.Applications.App

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "My Apps")
     |> assign(:confirmed?, Scope.confirmed?(socket.assigns.current_scope))
     |> assign(:created, nil)
     |> assign(:app_form, to_form(Applications.change_app(%App{})))
     |> stream_configure(:apps, dom_id: &"app-#{&1.slug}")
     |> assign_apps()}
  end

  # Apps are sorted by slug, so a new one resets the stream rather than
  # being inserted at an end.
  defp assign_apps(socket) do
    apps = Applications.list_apps_with_topic_counts(socket.assigns.current_scope)

    socket
    |> assign(:apps_count, length(apps))
    |> stream(:apps, apps, reset: true)
  end

  @impl true
  def handle_event("validate_app", %{"app" => params}, socket) do
    changeset = Applications.change_app(%App{}, params)
    {:noreply, assign(socket, :app_form, to_form(changeset, action: :validate))}
  end

  def handle_event("create_app", %{"app" => params}, socket) do
    case Applications.create_app(socket.assigns.current_scope, params) do
      {:ok, app} ->
        {:noreply,
         socket
         |> assign(:app_form, to_form(Applications.change_app(%App{})))
         |> assign(:created, app)
         |> assign_apps()}

      {:error, :unconfirmed} ->
        {:noreply, put_flash(socket, :error, "Confirm your email to create more apps.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :app_form, to_form(changeset))}
    end
  end

  def handle_event("dismiss_created", _params, socket) do
    {:noreply, assign(socket, :created, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:apps}>
      <section id="hero" class="mb-10 sm:mb-12">
        <span class="inline-flex items-center gap-2 rounded-full border border-base-content/10 bg-base-100/60 px-3 py-1 text-xs font-medium text-base-content/70">
          <span class="relative flex size-2">
            <span class="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60" />
            <span class="relative inline-flex size-2 rounded-full bg-success" />
          </span>
          Real-time pub/sub over HTTP &amp; WebSockets
        </span>
        <h1 class="mt-4 text-3xl font-semibold tracking-tight sm:text-4xl">My Apps</h1>
        <p class="mt-2 max-w-xl text-base-content/60">
          Each application owns the topics under its name, publishes with its own credentials
          and decides which websites may listen.
        </p>
      </section>

      <div class="grid gap-8 lg:grid-cols-3">
        <section class="lg:col-span-2">
          <div class="mb-4 flex items-baseline justify-between">
            <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
              Applications
            </h2>
            <span id="apps-count" class="text-sm tabular-nums text-base-content/50">
              {@apps_count} {if @apps_count == 1, do: "app", else: "apps"}
            </span>
          </div>

          <div id="apps" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
            <div
              id="apps-empty"
              class="hidden only:flex flex-col items-center rounded-2xl border border-dashed border-base-content/15 px-6 py-14 text-center sm:col-span-2"
            >
              <span class="grid size-12 place-items-center rounded-full bg-base-content/5">
                <.icon name="hero-cube-transparent" class="size-6 text-base-content/40" />
              </span>
              <p class="mt-4 font-medium">No applications yet</p>
              <p class="mt-1 text-sm text-base-content/50">
                Create your first application, then publish to its topics with its credentials.
              </p>
            </div>
            <.link
              :for={{id, app} <- @streams.apps}
              id={id}
              navigate={~p"/apps/#{app.slug}/topics"}
              class="group flex flex-col rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm transition-all duration-200 hover:-translate-y-0.5 hover:border-primary/40 hover:shadow-md hover:shadow-primary/5"
            >
              <span class="flex items-center gap-3">
                <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary transition-colors group-hover:bg-primary group-hover:text-primary-content">
                  <.icon name="hero-cube" class="size-5" />
                </span>
                <span class="min-w-0 flex-1 truncate font-mono font-semibold">{app.slug}</span>
                <.icon
                  name="hero-arrow-right"
                  class="size-4 shrink-0 text-base-content/30 transition-all group-hover:translate-x-0.5 group-hover:text-primary"
                />
              </span>
              <span class="mt-4 flex items-center justify-between gap-2 text-xs text-base-content/50">
                <span id={"#{id}-topics"} class="tabular-nums">
                  {app.topics_count} {if app.topics_count == 1, do: "topic", else: "topics"}
                </span>
                <code class="truncate font-mono">{app.client_id}</code>
              </span>
            </.link>
          </div>
        </section>

        <aside class="space-y-6">
          <div
            :if={@created}
            id="created"
            class="rounded-2xl border border-primary/30 bg-base-100 p-5 shadow-lg shadow-primary/10 ring-1 ring-primary/20"
          >
            <div class="flex items-start justify-between gap-2">
              <h2 class="flex items-center gap-2 font-semibold">
                <.icon name="hero-key" class="size-5 text-primary" />
                <span><span class="font-mono">{@created.slug}</span> created</span>
              </h2>
              <button
                id="dismiss-created"
                type="button"
                phx-click="dismiss_created"
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
                value={@created.client_id}
              />
              <.credential_row
                id="credentials-secret"
                label="Secret"
                value={@created.secret}
                secret
              />
              <p class="flex gap-2 text-xs text-base-content/70">
                <.icon name="hero-exclamation-triangle-micro" class="size-4 shrink-0 text-warning" />
                Store this secret now. It won't be shown again.
              </p>
              <.link
                id="open-created"
                navigate={~p"/apps/#{@created.slug}/topics"}
                class="inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline"
              >
                Open {@created.slug} <.icon name="hero-arrow-right-micro" class="size-4" />
              </.link>
            </div>
          </div>

          <div class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm">
            <h2 class="flex items-center gap-2 font-semibold">
              <.icon name="hero-plus-circle" class="size-5 text-primary" /> New application
            </h2>
            <p class="mt-1 text-sm text-base-content/50">
              Its name prefixes every topic it owns. It can't be renamed later.
            </p>
            <p
              :if={!@confirmed?}
              id="app-form-locked"
              class="mt-4 flex gap-2 rounded-lg bg-warning/10 px-3 py-2 text-xs text-base-content/70"
            >
              <.icon name="hero-envelope-micro" class="size-4 shrink-0 text-warning" />
              Confirm your email to create more apps. Until then, try things out in your sandbox app.
            </p>
            <.form
              :if={@confirmed?}
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
        </aside>
      </div>
    </Layouts.app>
    """
  end
end
