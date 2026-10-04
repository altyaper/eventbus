defmodule EventbusWeb.AppComponents do
  @moduledoc """
  Pieces shared by the My Apps pages: the per-app shell with its section
  menu, the copyable credential rows, and chat display helpers.
  """

  use EventbusWeb, :html

  @sections [
    topics: {"Topics", "hero-signal"},
    chat: {"Chat", "hero-chat-bubble-left-right"},
    credentials: {"Credentials", "hero-key"},
    origins: {"Origins", "hero-globe-alt"},
    settings: {"Settings", "hero-cog-6-tooth"}
  ]

  @doc """
  The path of one of `slug`'s sections.
  """
  def section_path(slug, :topics), do: ~p"/apps/#{slug}/topics"
  def section_path(slug, :chat), do: ~p"/apps/#{slug}/chat"
  def section_path(slug, :credentials), do: ~p"/apps/#{slug}/credentials"
  def section_path(slug, :origins), do: ~p"/apps/#{slug}/origins"
  def section_path(slug, :settings), do: ~p"/apps/#{slug}/settings"

  @doc """
  The frame of every page inside an app: breadcrumb, app header and the
  section menu (a sidebar on desktop, tabs on mobile). Section links patch, so `AppLive` doesn't remount.
  """
  attr :app, Eventbus.Applications.App, required: true
  attr :active, :atom, required: true, doc: "the highlighted section"
  attr :crumb, :string, default: nil, doc: "an extra breadcrumb after the app, e.g. a topic"
  attr :crumb_parent, :atom, default: :topics, doc: "the section the app breadcrumb links to"
  slot :inner_block, required: true

  def app_shell(assigns) do
    sections =
      for {key, {label, icon}} <- @sections, do: %{key: key, label: label, icon: icon}

    assigns = assign(assigns, :sections, sections)

    ~H"""
    <nav id="breadcrumb" class="mb-4 flex items-center gap-1.5 text-sm text-base-content/50">
      <.link navigate={~p"/apps"} class="transition-colors hover:text-base-content">My Apps</.link>
      <.icon name="hero-chevron-right-micro" class="size-4" />
      <%= if @crumb do %>
        <.link
          navigate={section_path(@app.slug, @crumb_parent)}
          class="font-mono transition-colors hover:text-base-content"
        >
          {@app.slug}
        </.link>
        <.icon name="hero-chevron-right-micro" class="size-4" />
        <span class="truncate font-mono text-base-content/80">{@crumb}</span>
      <% else %>
        <span class="font-mono text-base-content/80">{@app.slug}</span>
      <% end %>
    </nav>

    <header class="mb-8 flex items-center gap-3">
      <span class="grid size-11 place-items-center rounded-xl bg-gradient-to-br from-primary/20 to-accent/20 text-primary ring-1 ring-primary/20">
        <.icon name="hero-cube" class="size-6" />
      </span>
      <div class="min-w-0">
        <h1 id="app-title" class="truncate font-mono text-2xl font-semibold tracking-tight">
          {@app.slug}
        </h1>
        <p class="text-sm text-base-content/50">
          Owns every topic named <code class="font-mono">{@app.slug}.*</code>
        </p>
      </div>
    </header>

    <div class="grid gap-6 md:grid-cols-[12rem_1fr] md:gap-10">
      <nav
        id="app-sections"
        class="-mx-1 flex gap-1 overflow-x-auto border-b border-base-content/10 pb-2 md:mx-0 md:flex-col md:self-start md:border-b-0 md:pb-0"
      >
        <.link
          :for={section <- @sections}
          id={"section-#{section.key}"}
          patch={section_path(@app.slug, section.key)}
          aria-current={section.key == @active && "page"}
          class={[
            "flex shrink-0 items-center gap-2.5 rounded-lg px-2.5 py-2 text-sm font-medium transition-all duration-150 sm:px-3",
            if(section.key == @active,
              do: "bg-primary/10 text-primary",
              else: "text-base-content/60 hover:bg-base-content/5 hover:text-base-content"
            )
          ]}
        >
          <.icon name={section.icon} class="hidden size-4 sm:inline-block" />
          {section.label}
        </.link>
      </nav>

      <div class="min-w-0">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  A labelled value with a copy button; `secret` highlights it as shown-once.
  """
  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :secret, :boolean, default: false

  def credential_row(assigns) do
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
    """
  end

  @doc """
  A dark code snippet with an optional caption and a copy button.
  """
  attr :id, :string, required: true
  attr :code, :string, required: true
  attr :caption, :string, default: nil

  def code_block(assigns) do
    ~H"""
    <figure class="group/code relative mt-3 overflow-hidden rounded-xl bg-neutral text-neutral-content shadow-sm">
      <figcaption
        :if={@caption}
        class="border-b border-neutral-content/10 px-4 py-2 font-mono text-[0.7rem] text-neutral-content/50"
      >
        {@caption}
      </figcaption>
      <button
        id={"#{@id}-copy"}
        type="button"
        phx-hook=".CopyText"
        data-copy-target={"##{@id}"}
        class="absolute right-2 top-2 rounded-md p-1.5 text-neutral-content/50 opacity-0 transition-all hover:bg-neutral-content/10 hover:text-neutral-content focus:opacity-100 group-hover/code:opacity-100"
        aria-label="Copy code"
      >
        <.icon name="hero-clipboard-document" class="size-4 copy-idle" />
        <.icon name="hero-check" class="hidden size-4 text-success copy-done" />
      </button>
      <pre
        id={@id}
        class="overflow-x-auto p-4 font-mono text-xs leading-relaxed"
      >{@code}</pre>
    </figure>
    """
  end

  @doc """
  A card for a section's content.
  """
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <section
      id={@id}
      class={["rounded-2xl border border-base-content/10 bg-base-100 p-5 shadow-sm sm:p-6", @class]}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  def confirm_in,
    do: {"transition ease-out duration-150", "opacity-0 scale-95", "opacity-100 scale-100"}

  @doc """
  How a chat room is named in the admin UI: its name, or "Direct message"
  for direct rooms, which have none.
  """
  def room_label(%{type: "direct"}), do: "Direct message"
  def room_label(%{name: name}), do: name

  @doc """
  The icon for a chat room type.
  """
  def room_icon("direct"), do: "hero-user"
  def room_icon("public"), do: "hero-hashtag"
  def room_icon(_group), do: "hero-lock-closed"
end
