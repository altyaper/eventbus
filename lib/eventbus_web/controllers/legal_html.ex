defmodule EventbusWeb.LegalHTML do
  @moduledoc """
  The Privacy Policy and Terms of Service. Drafts: review the wording before
  opening signups to the public, and bump `last_updated/0` on every change.
  """

  use EventbusWeb, :html

  embed_templates "legal_html/*"

  def last_updated, do: "October 4, 2026"

  @doc """
  The frame shared by both pages: title, date and readable prose.
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def legal_page(assigns) do
    ~H"""
    <article id={@id} class="mx-auto max-w-2xl">
      <header class="mb-10 border-b border-base-content/10 pb-8">
        <p class="text-xs font-semibold uppercase tracking-wider text-primary">Legal</p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">{@title}</h1>
        <p id="last-updated" class="mt-3 text-sm text-base-content/50">
          Last updated {last_updated()}
        </p>
      </header>
      <div class="space-y-8 text-[15px] leading-relaxed text-base-content/80 [&_h2]:mb-3 [&_h2]:text-lg [&_h2]:font-semibold [&_h2]:text-base-content [&_ul]:list-disc [&_ul]:space-y-1.5 [&_ul]:pl-5 [&_a]:font-medium [&_a]:text-primary [&_a:hover]:underline">
        {render_slot(@inner_block)}
      </div>
    </article>
    """
  end
end
