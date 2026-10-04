defmodule EventbusWeb.LoginLive do
  use EventbusWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)

    {:ok,
     socket
     |> assign(:page_title, "Log in")
     |> assign(:form, to_form(%{"email" => email}, as: "user"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.auth_card icon="hero-lock-closed" title="Log in">
        <:subtitle>Welcome back. Sign in to watch your topics.</:subtitle>

        <.form for={@form} id="login-form" action={~p"/login"} class="space-y-1">
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            phx-mounted={JS.focus()}
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="Password"
            autocomplete="current-password"
            required
          />
          <div class="-mt-1 flex justify-end">
            <.link
              id="forgot-password-link"
              navigate={~p"/reset-password"}
              class="text-xs font-medium text-base-content/60 transition-colors hover:text-primary"
            >
              Forgot your password?
            </.link>
          </div>
          <button
            id="login-submit"
            type="submit"
            class="!mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Log in <.icon name="hero-arrow-right-micro" class="size-4" />
          </button>
        </.form>

        <p class="mt-6 text-center text-sm text-base-content/60">
          New to eventbus?
          <.link
            id="signup-link"
            navigate={~p"/signup"}
            class="font-medium text-primary hover:underline"
          >
            Create an account
          </.link>
        </p>
      </Layouts.auth_card>
    </Layouts.app>
    """
  end
end
