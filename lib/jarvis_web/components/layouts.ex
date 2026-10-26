defmodule JarvisWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use JarvisWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  # The display settings script runs in <head>, before the first paint.
  @display_js Path.expand("../../../assets/js/display.js", __DIR__)
  @external_resource @display_js
  @display_script File.read!(@display_js)

  @doc "The script that applies the reader's display settings; see `assets/js/display.js`."
  def display_script, do: @display_script

  @nav [
    {"nav-projects", "Projects", "/"},
    {"nav-docs", "Docs", "/docs"},
    {"nav-guide", "Guide", "/guide"},
    {"nav-design-system", "Design system", "/design-system"},
    {"nav-settings", "Settings", "/settings"}
  ]

  @doc """
  The shell every page is drawn in: a skip link, the main navigation (always
  the same links in the same order), breadcrumbs, and the main landmark.

  The rules this shell must keep are in `.agents/skills/jarvis-design`.

      <Layouts.app flash={@flash} theme_css={@theme_css} form={:reference}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :crumbs, :list,
    default: [],
    doc:
      "breadcrumbs after the home link, as `{label, path}` tuples; the last is the current page"

  attr :theme_css, :string, default: nil, doc: "the theme derived from the brand colors"

  attr :form, :atom,
    required: true,
    values: [:tutorial, :how_to, :reference, :explanation],
    doc: "the page's Diátaxis form (see `JarvisWeb.Diataxis`)"

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :nav, @nav)

    ~H"""
    <style :if={@theme_css} id="brand-theme">
      <%= Phoenix.HTML.raw(@theme_css) %>
    </style>
    <a
      href="#main"
      id="skip-link"
      class="sr-only focus:not-sr-only focus:fixed focus:left-3 focus:top-3 focus:z-50 focus:rounded-lg focus:bg-base-content focus:px-4 focus:py-2 focus:text-base-100"
    >
      Skip to content
    </a>
    <header id="shell-header" class="border-b border-base-300 bg-base-100">
      <div class="mx-auto flex max-w-7xl flex-wrap items-center gap-x-4 gap-y-2 px-4 py-2 sm:px-6">
        <.link
          navigate={~p"/"}
          id="shell-home"
          class="flex min-h-11 items-center gap-2 font-semibold tracking-tight"
        >
          <span
            aria-hidden="true"
            class="grid size-7 place-items-center rounded-lg bg-primary text-primary-content"
          >
            <.icon name="hero-cpu-chip" class="size-4" />
          </span>
          Jarvis
        </.link>
        <nav id="main-nav" aria-label="Main" class="sm:ml-auto">
          <ul class="flex flex-wrap items-center gap-1">
            <li :for={{id, label, path} <- @nav}>
              <.link
                id={id}
                navigate={path}
                class="inline-flex min-h-11 items-center rounded-lg px-3 text-sm font-medium text-base-content/80 transition hover:bg-base-200 hover:text-base-content"
              >
                {label}
              </.link>
            </li>
          </ul>
        </nav>
      </div>
      <nav
        :if={@crumbs != []}
        id="breadcrumbs"
        aria-label="Breadcrumb"
        class="mx-auto max-w-7xl px-4 pb-2 sm:px-6"
      >
        <ol class="flex flex-wrap items-center gap-1 text-sm">
          <li class="flex items-center">
            <.link navigate={~p"/"} class="rounded px-1.5 py-1 text-base-content/80 hover:underline">
              Projects
            </.link>
          </li>
          <li :for={{{label, path}, i} <- Enum.with_index(@crumbs)} class="flex min-w-0 items-center">
            <span aria-hidden="true" class="px-0.5 text-base-content/70">/</span>
            <.link
              navigate={path}
              aria-current={if i == length(@crumbs) - 1, do: "page"}
              class={[
                "rounded px-1.5 py-1 break-words hover:underline",
                if(i == length(@crumbs) - 1, do: "font-semibold", else: "text-base-content/80")
              ]}
            >
              {label}
            </.link>
          </li>
        </ol>
      </nav>
    </header>

    <main id="main" tabindex="-1" class="mx-auto max-w-7xl px-4 py-8 outline-none sm:px-6">
      <p id="page-form" class="mb-4 flex flex-wrap items-center gap-2 text-sm text-base-content/80">
        <.form_badge form={@form} />
        <span>{JarvisWeb.Diataxis.purpose(@form)}</span>
      </p>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
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
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
