defmodule EventbusWeb.SetupLive do
  @moduledoc """
  First-run setup: creates the superadmin. Only reachable while no user
  exists; proving ownership requires the instance API key, which is printed
  in the server logs until setup is done.
  """

  use EventbusWeb, :live_view

  alias Eventbus.{Accounts, Settings}
  alias Eventbus.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Set up eventbus")
     |> assign(:trigger_submit, false)
     |> assign_form(Accounts.change_user_registration(%User{}))}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    if valid_api_key?(user_params["api_key"]) do
      create_superadmin(socket, user_params)
    else
      changeset =
        %User{}
        |> Accounts.change_user_registration(user_params)
        |> Ecto.Changeset.add_error(:api_key, "doesn't match this server's API key")
        |> Map.put(:action, :insert)

      {:noreply, assign_form(socket, changeset)}
    end
  end

  defp create_superadmin(socket, user_params) do
    case Accounts.create_superadmin(user_params) do
      {:ok, _user} ->
        # Keep the submitted values in the form: phx-trigger-action posts it to
        # the session controller, which logs the new superadmin in.
        {:noreply,
         socket
         |> assign(:form, to_form(user_params, as: "user"))
         |> assign(:trigger_submit, true)}

      {:error, :already_set_up} ->
        {:noreply,
         socket
         |> put_flash(:error, "eventbus is already set up. Log in instead.")
         |> push_navigate(to: ~p"/login")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp valid_api_key?(given) when is_binary(given) and given != "" do
    Plug.Crypto.secure_compare(String.trim(given), Settings.api_key())
  end

  defp valid_api_key?(_given), do: false

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.auth_card icon="hero-sparkles" title="Welcome to eventbus">
        <:subtitle>
          Create the superadmin account. You'll be able to invite more people later.
        </:subtitle>

        <.form
          for={@form}
          id="setup-form"
          action={~p"/login"}
          phx-change="validate"
          phx-submit="save"
          phx-trigger-action={@trigger_submit}
          class="space-y-1"
        >
          <.input
            field={@form[:username]}
            label="Username"
            placeholder="admin"
            autocomplete="username"
            phx-debounce="300"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="new-password"
            phx-debounce="300"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm password"
            autocomplete="new-password"
            phx-debounce="300"
            required
          />

          <div class="!mt-5 rounded-2xl border border-dashed border-base-content/15 p-4">
            <.input
              field={@form[:api_key]}
              type="password"
              label="Server API key"
              placeholder="eb_…"
              autocomplete="off"
              required
            />
            <p class="flex gap-2 text-xs text-base-content/50">
              <.icon name="hero-command-line-micro" class="size-4 shrink-0" />
              <span>
                Proves you own this server. Find it in the logs, e.g.
                <code class="font-mono text-base-content/70">docker compose logs app</code>
              </span>
            </p>
          </div>

          <button
            id="setup-submit"
            type="submit"
            phx-disable-with="Creating account…"
            class="!mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Create superadmin <.icon name="hero-arrow-right-micro" class="size-4" />
          </button>
        </.form>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end
end
