defmodule EventbusWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EventbusWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :nav, :atom, default: nil, doc: "the highlighted top-menu entry, e.g. `:apps`"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="relative min-h-screen overflow-hidden">
      <div aria-hidden="true" class="dot-field pointer-events-none fixed inset-0 -z-20" />
      <div
        aria-hidden="true"
        class="pointer-events-none absolute inset-x-0 -top-40 -z-10 h-[28rem] bg-gradient-to-b from-primary/15 via-primary/5 to-transparent blur-2xl"
      />

      <header class="sticky top-0 z-20 border-b border-base-content/5 bg-base-100/70 backdrop-blur-md">
        <div class="mx-auto flex h-16 max-w-6xl items-center justify-between px-4 sm:px-6 lg:px-8">
          <.link navigate={~p"/apps"} id="brand" class="group flex items-center gap-2.5">
            <span class="grid size-8 place-items-center rounded-lg bg-gradient-to-br from-primary to-accent text-primary-content shadow-sm shadow-primary/30 transition-transform duration-300 group-hover:rotate-6 group-hover:scale-105">
              <.icon name="hero-bolt-solid" class="size-4" />
            </span>
            <span class="text-base font-semibold tracking-tight">eventbus</span>
          </.link>

          <nav class="flex items-center gap-2 sm:gap-4">
            <.link
              :if={@current_scope}
              id="nav-apps"
              navigate={~p"/apps"}
              aria-current={@nav == :apps && "page"}
              class={[
                "flex items-center gap-1.5 whitespace-nowrap rounded-md px-3 py-1.5 text-sm font-medium transition-colors",
                if(@nav == :apps,
                  do: "bg-primary/10 text-primary",
                  else: "text-base-content/70 hover:bg-base-content/5 hover:text-base-content"
                )
              ]}
            >
              <.icon name="hero-squares-2x2-micro" class="hidden size-4 sm:inline-block" /> My Apps
            </.link>
            <.theme_toggle />
            <.user_menu :if={@current_scope} current_scope={@current_scope} />
          </nav>
        </div>
      </header>

      <main class="px-4 py-10 sm:px-6 sm:py-14 lg:px-8">
        <div class="mx-auto max-w-6xl">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The logged-in user's menu: username, role and log out.
  """
  attr :current_scope, Eventbus.Accounts.Scope, required: true

  def user_menu(assigns) do
    ~H"""
    <div class="relative" phx-click-away={JS.hide(to: "#user-menu-panel", transition: menu_out())}>
      <button
        id="user-menu-button"
        type="button"
        phx-click={JS.toggle(to: "#user-menu-panel", in: menu_in(), out: menu_out())}
        class="flex items-center gap-2 rounded-full border border-base-content/10 py-1 pr-3 pl-1 text-sm font-medium transition-colors hover:border-base-content/20 hover:bg-base-content/5"
      >
        <span class="grid size-7 place-items-center rounded-full bg-primary/15 text-xs font-semibold uppercase text-primary">
          {String.first(@current_scope.user.username)}
        </span>
        <span class="hidden sm:inline">{@current_scope.user.username}</span>
        <.icon name="hero-chevron-down-micro" class="size-4 text-base-content/50" />
      </button>

      <div
        id="user-menu-panel"
        class="absolute right-0 z-30 mt-2 hidden w-80 origin-top-right rounded-2xl border border-base-content/10 bg-base-100 p-2 shadow-xl shadow-base-content/10"
      >
        <div class="flex items-center justify-between px-3 py-2">
          <div class="min-w-0">
            <p class="truncate text-sm font-semibold">{@current_scope.user.username}</p>
            <p class="text-xs text-base-content/50">Signed in</p>
          </div>
          <span
            id="user-role"
            class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
          >
            {@current_scope.user.role}
          </span>
        </div>

        <.link
          id="log-out"
          href={~p"/logout"}
          method="delete"
          class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm text-base-content/70 transition-colors hover:bg-base-content/5 hover:text-base-content"
        >
          <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> Log out
        </.link>
      </div>
    </div>
    """
  end

  defp menu_in,
    do: {"transition ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"}

  defp menu_out,
    do: {"transition ease-in duration-100", "opacity-100 scale-100", "opacity-0 scale-95"}

  @doc """
  Centered card used by the setup and login pages.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  slot :subtitle
  slot :inner_block, required: true

  def auth_card(assigns) do
    ~H"""
    <div class="mx-auto mt-4 max-w-md sm:mt-10">
      <div class="rounded-3xl border border-base-content/10 bg-base-100/90 p-6 shadow-xl shadow-base-content/5 backdrop-blur sm:p-8">
        <span class="grid size-12 place-items-center rounded-2xl bg-gradient-to-br from-primary to-accent text-primary-content shadow-md shadow-primary/30">
          <.icon name={@icon} class="size-6" />
        </span>
        <h1 class="mt-5 text-2xl font-semibold tracking-tight">{@title}</h1>
        <p :if={@subtitle != []} class="mt-1.5 text-sm text-base-content/60">
          {render_slot(@subtitle)}
        </p>
        <div class="mt-6">{render_slot(@inner_block)}</div>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
