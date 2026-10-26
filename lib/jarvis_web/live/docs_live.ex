defmodule JarvisWeb.DocsLive do
  @moduledoc """
  The documentation start page, which lists the four Diátaxis forms with the
  page of each, and the tutorial that walks a first comment loop.
  """
  use JarvisWeb, :live_view

  alias JarvisWeb.Diataxis

  @pages %{
    tutorial: {"/docs/tutorial", "Your first comment loop"},
    how_to: {"/settings", "Settings: language, colors, display, integrations"},
    reference: {"/design-system", "Design system: every widget kind"},
    explanation: {"/guide", "Guide: goals, tasks, steps, and workflows"}
  }

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _uri, socket) do
    title = if socket.assigns.live_action == :tutorial, do: "Tutorial", else: "Docs"
    {:noreply, assign(socket, :page_title, title)}
  end

  @impl true
  def render(%{live_action: :tutorial} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      form={:tutorial}
      crumbs={[{"Docs", ~p"/docs"}, {"Tutorial", ~p"/docs/tutorial"}]}
    >
      <article class="max-w-[70ch] space-y-8">
        <h1 class="text-2xl font-semibold tracking-tight">Your first comment loop</h1>

        <section id="tutorial-outcome">
          <h2 class="text-lg font-semibold">What you can do afterwards</h2>
          <p class="mt-2">
            You can point at one part of a widget and ask the agent about it. The answer shows in the same place.
          </p>
        </section>

        <section id="tutorial-steps">
          <h2 class="text-lg font-semibold">Steps</h2>
          <ol class="mt-2 list-decimal space-y-2 pl-6">
            <li>
              Open
              <.link navigate={~p"/settings#integrations-panel"} class="underline">Settings</.link>
              and install Jarvis in your coding agent.
            </li>
            <li>Start the agent in a git repository.</li>
            <li>
              Type <code class="rounded bg-base-200 px-1">/learn how this repository starts</code>.
            </li>
            <li>Open the project on the board, then open the new Learn task.</li>
            <li>Choose Comment on one part of a widget.</li>
            <li>Write a question and choose Send comment.</li>
          </ol>
        </section>

        <section id="tutorial-check">
          <h2 class="text-lg font-semibold">Check your result</h2>
          <ul class="mt-2 list-disc space-y-2 pl-6">
            <li>Your question shows in the thread under that part.</li>
            <li>The thread says when the agent will hear it.</li>
            <li>The agent's answer shows in the same thread after its next turn.</li>
          </ul>
        </section>
      </article>
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, forms: Diataxis.all(), pages: @pages)

    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      form={:reference}
      crumbs={[{"Docs", ~p"/docs"}]}
    >
      <h1 class="text-2xl font-semibold tracking-tight">Docs</h1>
      <p class="mt-2 max-w-[70ch]">Each page has one purpose. Pick the one that fits your need.</p>
      <ul id="doc-forms" class="mt-6 grid max-w-3xl gap-3">
        <li
          :for={{form, label, purpose} <- @forms}
          id={"doc-form-#{form}"}
          class="rounded-2xl border border-base-300 bg-base-100 p-4"
        >
          <% {path, page} = @pages[form] %>
          <h2 class="font-semibold">{label}</h2>
          <p class="text-sm">{purpose}</p>
          <.link navigate={path} class="mt-1 inline-block text-sm font-medium underline">
            {page}
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
