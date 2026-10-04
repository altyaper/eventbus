defmodule EventbusWeb.ResetPasswordRequestLive do
  @moduledoc """
  Asks for an email and sends a password reset link. Answers the same way
  whether or not the email has an account.
  """

  use EventbusWeb, :live_view

  alias Eventbus.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Reset your password")
     |> assign(:form, to_form(%{"email" => ""}, as: "user"))}
  end

  @impl true
  def handle_event("send", %{"user" => %{"email" => email}}, socket) do
    :ok =
      Accounts.deliver_user_reset_password_instructions(email, &url(~p"/reset-password/#{&1}"))

    {:noreply,
     socket
     |> put_flash(
       :info,
       "If that email has an account, we've sent it a link to reset the password."
     )
     |> push_navigate(to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.auth_card icon="hero-key" title="Reset your password">
        <:subtitle>We'll email you a link to choose a new one.</:subtitle>

        <.form for={@form} id="reset-request-form" phx-submit="send" class="space-y-1">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            phx-mounted={JS.focus()}
            required
          />
          <button
            id="reset-request-submit"
            type="submit"
            phx-disable-with="Sending…"
            class="!mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Send reset link <.icon name="hero-paper-airplane-micro" class="size-4" />
          </button>
        </.form>

        <p class="mt-6 text-center text-sm text-base-content/60">
          Remembered it?
          <.link
            id="login-link"
            navigate={~p"/login"}
            class="font-medium text-primary hover:underline"
          >
            Log in
          </.link>
        </p>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end
end
