defmodule EventbusWeb.SignupLive do
  @moduledoc """
  Public signup. Creates the account and its sandbox app, emails a
  confirmation link and logs the new user in straight away; confirming later
  lifts the unconfirmed limits.
  """

  use EventbusWeb, :live_view

  alias Eventbus.Accounts
  alias Eventbus.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign up")
     |> assign(:trigger_submit, false)
     |> assign_form(Accounts.change_user_signup(%User{}))}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_signup(%User{}, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:ok, _email} =
          Accounts.deliver_user_confirmation_instructions(user, &url(~p"/confirm/#{&1}"))

        # Keep the submitted values in the form: phx-trigger-action posts it to
        # the session controller, which logs the new user in.
        {:noreply,
         socket
         |> assign(:form, to_form(user_params, as: "user"))
         |> assign(:trigger_submit, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: "user"))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <Layouts.auth_card icon="hero-rocket-launch" title="Create your account">
        <:subtitle>
          You get a sandbox app to publish your first events right away.
        </:subtitle>

        <.form
          for={@form}
          id="signup-form"
          action={~p"/login"}
          phx-change="validate"
          phx-submit="save"
          phx-trigger-action={@trigger_submit}
          class="space-y-1"
        >
          <.input
            field={@form[:email]}
            type="email"
            label="Email"
            placeholder="you@example.com"
            autocomplete="username"
            phx-debounce="300"
            phx-mounted={JS.focus()}
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

          <.terms_checkbox field={@form[:terms]} />

          <button
            id="signup-submit"
            type="submit"
            phx-disable-with="Creating account…"
            class="!mt-6 inline-flex w-full items-center justify-center gap-2 rounded-full bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-[0.98]"
          >
            Create account <.icon name="hero-arrow-right-micro" class="size-4" />
          </button>
        </.form>

        <p class="mt-6 text-center text-sm text-base-content/60">
          Already have an account?
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

  # `<.input type="checkbox">` only takes a plain-text label; this one links
  # to the legal pages.
  attr :field, Phoenix.HTML.FormField, required: true

  defp terms_checkbox(assigns) do
    assigns =
      assign(
        assigns,
        :errors,
        if(Phoenix.Component.used_input?(assigns.field),
          do: Enum.map(assigns.field.errors, &translate_error/1),
          else: []
        )
      )

    ~H"""
    <div class="!mt-4">
      <label for={@field.id} class="flex cursor-pointer items-start gap-2.5 text-sm">
        <input type="hidden" name={@field.name} value="false" />
        <input
          type="checkbox"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={Phoenix.HTML.Form.normalize_value("checkbox", @field.value)}
          class="checkbox checkbox-sm checkbox-primary mt-0.5"
        />
        <span class="text-base-content/70">
          I agree to the
          <.link href={~p"/terms"} target="_blank" class="font-medium text-primary hover:underline">
            Terms of Service
          </.link>
          and the
          <.link href={~p"/privacy"} target="_blank" class="font-medium text-primary hover:underline">
            Privacy Policy
          </.link>
        </span>
      </label>
      <p :for={msg <- @errors} class="mt-1.5 flex items-center gap-2 text-sm text-error">
        <.icon name="hero-exclamation-circle" class="size-5" /> {msg}
      </p>
    </div>
    """
  end
end
