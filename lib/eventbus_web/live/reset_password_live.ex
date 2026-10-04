defmodule EventbusWeb.ResetPasswordLive do
  @moduledoc """
  The page behind a reset link: sets a new password, which ends every
  session of the account. The user then logs in again.
  """

  use EventbusWeb, :live_view

  alias Eventbus.Accounts
  alias EventbusWeb.UserAuth

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      {:ok,
       socket
       |> assign(:page_title, "Choose a new password")
       |> assign(:user, user)
       |> assign_form(Accounts.change_user_password(user))}
    else
      {:ok,
       socket
       |> put_flash(:error, "That reset link is invalid or has expired.")
       |> push_navigate(to: ~p"/reset-password")}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("reset", %{"user" => params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, params) do
      {:ok, _user, session_tokens} ->
        UserAuth.disconnect_sessions(session_tokens)

        {:noreply,
         socket
         |> put_flash(:info, "Password changed. Log in with your new password.")
         |> push_navigate(to: ~p"/login")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: "user"))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.auth_card icon="hero-lock-open" title="Choose a new password">
        <:subtitle>
          For <strong class="font-semibold text-base-content">{@user.email}</strong>.
          This logs you out everywhere.
        </:subtitle>

        <.form
          for={@form}
          id="reset-password-form"
          phx-change="validate"
          phx-submit="reset"
          class="space-y-1"
        >
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            phx-debounce="300"
            phx-mounted={JS.focus()}
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
            phx-debounce="300"
            required
          />
          <button
            id="reset-password-submit"
            type="submit"
            phx-disable-with="Saving…"
            class="!mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Set new password <.icon name="hero-arrow-right-micro" class="size-4" />
          </button>
        </.form>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end
end
