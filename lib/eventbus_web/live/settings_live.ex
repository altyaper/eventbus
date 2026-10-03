defmodule EventbusWeb.SettingsLive do
  @moduledoc """
  Superadmin settings. Currently: which origins may open websockets.
  """

  use EventbusWeb, :live_view

  alias Eventbus.Origins
  alias Eventbus.Origins.AllowedOrigin

  @impl true
  def mount(_params, _session, socket) do
    origins = Origins.list_allowed_origins()

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:env_origins, Origins.env_origins())
     |> assign(:origin_checks_off?, origin_checks_off?())
     |> assign_form(Origins.change_allowed_origin(%AllowedOrigin{}))
     |> stream(:origins, origins)}
  end

  # In dev the endpoint has `check_origin: false`, so nothing here applies.
  defp origin_checks_off? do
    Application.get_env(:eventbus, EventbusWeb.Endpoint, [])[:check_origin] == false
  end

  @impl true
  def handle_event("validate", %{"allowed_origin" => params}, socket) do
    changeset = Origins.change_allowed_origin(%AllowedOrigin{}, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("add", %{"allowed_origin" => params}, socket) do
    case Origins.create_allowed_origin(params) do
      {:ok, allowed_origin} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{allowed_origin.origin} can now connect.")
         |> stream_insert(:origins, allowed_origin)
         |> assign_form(Origins.change_allowed_origin(%AllowedOrigin{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    case Origins.delete_allowed_origin(id) do
      {:ok, allowed_origin} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{allowed_origin.origin} removed.")
         |> stream_delete(:origins, allowed_origin)}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl">
        <section class="mb-8">
          <h1 class="text-3xl font-semibold tracking-tight">Settings</h1>
          <p class="mt-2 text-base-content/60">Instance-wide configuration for eventbus.</p>
        </section>

        <section
          id="allowed-origins"
          class="rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm sm:p-6"
        >
          <h2 class="flex items-center gap-2 font-semibold">
            <.icon name="hero-globe-alt" class="size-5 text-primary" /> Allowed origins
          </h2>
          <p class="mt-1 text-sm text-base-content/60">
            Web pages on these origins can open a WebSocket to eventbus: the
            <code class="font-mono text-base-content/80">/socket</code>
            API for browser apps, and this UI itself. Changes apply to new connections immediately.
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
            for={@form}
            id="origin-form"
            phx-change="validate"
            phx-submit="add"
            class="mt-5 flex items-start gap-2"
          >
            <div class="min-w-0 flex-1">
              <.input
                field={@form[:origin]}
                placeholder="https://changologs.com"
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
            Added here
          </h3>
          <ul id="origins" phx-update="stream" class="divide-y divide-base-content/5">
            <li id="origins-empty" class="hidden py-3 text-sm text-base-content/50 only:block">
              No extra origins yet.
            </li>
            <li
              :for={{id, allowed_origin} <- @streams.origins}
              id={id}
              class="group flex items-center gap-3 py-2.5"
            >
              <.icon name="hero-link" class="size-4 shrink-0 text-base-content/40" />
              <span class="min-w-0 flex-1 truncate font-mono text-sm">{allowed_origin.origin}</span>
              <button
                id={"#{id}-remove"}
                type="button"
                phx-click="remove"
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
              From the environment
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
              These can't be removed here, so you can't lock yourself out of this page.
              Change them in the server's environment variables.
            </p>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
