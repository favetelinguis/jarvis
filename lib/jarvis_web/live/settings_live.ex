defmodule JarvisWeb.SettingsLive do
  @moduledoc """
  Settings, as how-to steps: the reader's display settings (applied and kept
  in the browser by `assets/js/display.js`), the board language, the brand
  colors (previewed on sample widgets with the contrast of every text color),
  and the integrations.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Integrations, Integrations.Subagents, Language, Planning.Catalog, Theme}

  import JarvisWeb.WidgetComponents

  # Mirrors OPTIONS in assets/js/display.js, which applies and stores them.
  @display_options [
    {"textSize", "Text size",
     [{"100", "100%"}, {"125", "125%"}, {"150", "150%"}, {"200", "200%"}]},
    {"leading", "Line spacing", [{"normal", "Normal"}, {"increased", "Increased"}]},
    {"theme", "Color theme",
     [{"light", "Light"}, {"dark", "Dark"}, {"contrast", "High contrast"}]},
    {"motion", "Motion", [{"on", "On"}, {"reduced", "Reduced"}]},
    {"density", "Density", [{"airy", "Airy"}, {"compact", "Compact"}]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket),
        do: start_async(socket, :integrations, &Integrations.list/0),
        else: socket

    {:ok,
     socket
     |> assign(:integrations, [])
     |> assign(:page_title, "Settings")
     |> assign(:language, Language.current())
     |> assign(:display_options, @display_options)
     |> assign(:colors, Theme.current())
     |> assign(:errors, %{})
     |> assign(:saved?, Theme.custom?())
     |> preview()}
  end

  @impl true
  def handle_async(:integrations, {:ok, integrations}, socket),
    do: {:noreply, assign(socket, :integrations, integrations)}

  def handle_async(:integrations, {:exit, _reason}, socket), do: {:noreply, socket}

  @impl true
  def handle_event("install", %{"agent" => agent} = params, socket),
    do:
      {:noreply,
       change_integration(socket, agent, &Integrations.install(&1, params["subagents"] || %{}))}

  def handle_event("uninstall", %{"agent" => agent}, socket),
    do: {:noreply, change_integration(socket, agent, &Integrations.uninstall/1)}

  def handle_event("language", %{"language" => code}, socket) do
    case Language.save(code) do
      {:ok, code} -> {:noreply, assign(socket, :language, code)}
      {:error, _} -> {:noreply, socket}
    end
  end

  def handle_event("change", params, socket) do
    colors =
      case params["_target"] do
        ["picker", name] -> Map.put(socket.assigns.colors, name, params["picker"][name])
        _ -> Map.merge(socket.assigns.colors, params["colors"] || %{})
      end

    {:noreply, socket |> assign(:colors, colors) |> validate()}
  end

  def handle_event("save", %{"colors" => params}, socket) do
    case Theme.save(params) do
      {:ok, colors} ->
        {:noreply,
         socket
         |> assign(colors: colors, errors: %{}, saved?: true)
         |> preview()
         |> put_flash(:info, "Brand colors saved.")}

      {:error, errors} ->
        {:noreply,
         assign(socket, colors: Map.merge(socket.assigns.colors, params), errors: errors)}
    end
  end

  def handle_event("reset", _params, socket) do
    Theme.reset()

    {:noreply,
     socket |> assign(colors: Theme.defaults(), errors: %{}, saved?: false) |> preview()}
  end

  defp change_integration(socket, agent, fun) do
    case Enum.find(socket.assigns.integrations, &(Atom.to_string(&1.agent) == agent)) do
      nil ->
        socket

      current ->
        updated = fun.(current.agent)

        assign(
          socket,
          :integrations,
          Enum.map(
            socket.assigns.integrations,
            &if(&1.agent == updated.agent, do: updated, else: &1)
          )
        )
    end
  end

  defp integration_state_label(:installed), do: "Installed"
  defp integration_state_label(:partial), do: "Partly installed"
  defp integration_state_label(:not_installed), do: "Not installed"
  defp integration_state_label(:unreadable), do: "Unreadable"

  defp validate(socket) do
    case Theme.validate(socket.assigns.colors) do
      {:ok, _colors} -> socket |> assign(:errors, %{}) |> preview()
      {:error, errors} -> assign(socket, :errors, errors)
    end
  end

  defp preview(socket) do
    case Theme.validate(socket.assigns.colors) do
      {:ok, colors} ->
        socket
        |> assign(:preview_css, Theme.css(colors, "#preview"))
        |> assign(:contrast, contrast(colors))

      {:error, _} ->
        socket
    end
  end

  # The color input only takes #rrggbb; anything else leaves it black until the text is valid.
  defp picker_value(value) do
    case Theme.parse_hex(value) do
      {:ok, rgb} -> Theme.to_hex(rgb)
      :error -> "#000000"
    end
  end

  defp contrast(colors) do
    for mode <- [:light, :dark], {label, fg, bg} <- Theme.text_pairs(colors, mode) do
      {mode, label, Theme.contrast(fg, bg)}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        samples:
          for {kind, i} <- Enum.with_index(~w(requirement callout comparison), 1) do
            %Jarvis.Planning.Widget{
              id: -i,
              kind: kind,
              section: "sample",
              data: Catalog.example(kind),
              human: %{}
            }
          end,
        ctx: context(sandbox: true)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      theme_css={@theme_css}
      form={:how_to}
      crumbs={[{"Settings", ~p"/settings"}]}
    >
      <h1 class="text-2xl font-semibold tracking-tight">Settings</h1>
      <p class="mt-1 text-sm">
        Each section is one job in numbered steps.
        <.link navigate={~p"/guide"} class="underline">Read the Guide</.link>
        to learn why things work this way.
      </p>

      <section id="display-panel" class="mt-8 mb-10">
        <h2 class="text-xl font-semibold tracking-tight">Change how the board looks</h2>
        <ol id="display-steps" class="mt-2 list-decimal space-y-1 pl-6 text-sm">
          <li>Pick a value for each setting below.</li>
          <li>See the change at once, on this page and every page after it.</li>
          <li>Choose Reset to defaults to undo all of them.</li>
        </ol>
        <p class="mt-2 text-sm">This browser keeps your choices.</p>
        <form
          id="display-form"
          phx-hook="DisplaySettings"
          phx-update="ignore"
          class="mt-4 grid max-w-3xl gap-4 sm:grid-cols-2"
        >
          <fieldset
            :for={{name, legend, options} <- @display_options}
            id={"display-#{name}"}
            class="rounded-2xl border border-base-300 p-3"
          >
            <legend class="px-1 text-sm font-semibold">{legend}</legend>
            <div class="flex flex-wrap gap-2">
              <label
                :for={{value, label} <- options}
                class="inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-lg border border-base-300 px-3 text-sm has-checked:border-base-content has-checked:font-semibold has-checked:ring-2 has-checked:ring-base-content"
              >
                <input type="radio" name={name} value={value} id={"display-#{name}-#{value}"} />
                {label}
              </label>
            </div>
          </fieldset>
          <div class="sm:col-span-2">
            <button
              type="reset"
              id="display-reset"
              class="rounded-lg border border-base-300 px-4 py-1.5 text-sm font-medium hover:bg-base-200"
            >
              Reset to defaults
            </button>
          </div>
        </form>
      </section>

      <section id="language-panel" class="mb-10">
        <h2 class="text-xl font-semibold tracking-tight">Choose the board language</h2>
        <ol id="language-steps" class="mt-2 list-decimal space-y-1 pl-6 text-sm">
          <li>Pick a language in the list.</li>
          <li>Agents write new goals, tasks, widgets, and comments in it from their next turn.</li>
        </ol>
        <.form for={%{}} id="language-form" phx-change="language" class="mt-3">
          <label for="language" class="mb-1 block text-sm font-medium">Board language</label>
          <select
            id="language"
            name="language"
            class="rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 text-sm"
          >
            <option :for={{code, name} <- Language.all()} value={code} selected={code == @language}>
              {name}
            </option>
          </select>
        </.form>
      </section>

      <section id="brand-panel">
        <h2 class="text-xl font-semibold tracking-tight">Change the brand colors</h2>
        <ol id="brand-steps" class="mt-2 list-decimal space-y-1 pl-6 text-sm">
          <li>Type a hex color, or pick one, for primary, secondary, and accent.</li>
          <li>Check the preview and the contrast table.</li>
          <li>Choose Save colors.</li>
        </ol>

        <div class="mt-6 grid gap-6 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
          <.form
            for={%{}}
            id="brand-form"
            phx-change="change"
            phx-submit="save"
            class="space-y-4 self-start rounded-2xl border border-base-300 bg-base-100 p-4"
          >
            <div :for={name <- Theme.names()} class="space-y-1">
              <label for={"color-#{name}"} class="text-sm font-medium capitalize">{name}</label>
              <div class="flex items-center gap-2">
                <input
                  type="color"
                  aria-label={"Pick #{name}"}
                  value={picker_value(@colors[name])}
                  name={"picker[#{name}]"}
                  class="size-9 cursor-pointer rounded border border-base-300 bg-transparent p-0.5"
                />
                <input
                  id={"color-#{name}"}
                  type="text"
                  name={"colors[#{name}]"}
                  value={@colors[name]}
                  autocomplete="off"
                  phx-debounce="150"
                  class="w-full rounded-lg border border-base-300 bg-base-100 px-3 py-1.5 font-mono text-sm"
                />
              </div>
              <p :if={@errors[name]} id={"error-#{name}"} class="text-sm text-error">
                {String.capitalize(name)}: {@errors[name]}
              </p>
            </div>
            <div class="flex gap-2 pt-2">
              <button
                type="submit"
                id="save-colors"
                class="rounded-lg bg-primary px-4 py-1.5 text-sm font-medium text-primary-content hover:opacity-90"
              >Save colors</button>
              <button
                type="button"
                id="reset-colors"
                phx-click="reset"
                disabled={!@saved?}
                class="rounded-lg border border-base-300 px-4 py-1.5 text-sm font-medium hover:bg-base-200 disabled:opacity-40"
              >
                Reset to default
              </button>
            </div>
          </.form>

          <div class="space-y-4">
            <style id="preview-theme">
              <%= Phoenix.HTML.raw(@preview_css) %>
            </style>
            <div id="preview" class="space-y-3 rounded-2xl border border-dashed border-base-300 p-3">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Preview (not saved until you press Save)
              </p>
              <.widget :for={w <- @samples} w={w} ctx={@ctx} />
            </div>

            <div class="rounded-2xl border border-base-300 bg-base-100 p-4">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
                Contrast of text (minimum 4.5)
              </p>
              <table class="mt-2 w-full text-sm" id="contrast-table">
                <tbody>
                  <tr :for={{mode, label, ratio} <- @contrast} class="border-t border-base-200">
                    <td class="py-1 capitalize text-base-content/70">{mode}</td>
                    <td class="py-1">{label}</td>
                    <td class={[
                      "py-1 text-right font-mono",
                      ratio >= 4.5 && "text-success",
                      ratio < 4.5 && "text-error"
                    ]}>
                      {Float.round(ratio, 2)}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </section>
      <section id="integrations-panel" class="mt-10">
        <h2 class="text-xl font-semibold tracking-tight">Install Jarvis in a coding agent</h2>
        <ol id="integration-steps" class="mt-2 list-decimal space-y-1 pl-6 text-sm">
          <li>Find your agent in the list.</li>
          <li>Optional: set a model and an effort for each subagent.</li>
          <li>Choose Install. Choose it again after a change to update the subagents.</li>
          <li>Restart the agent, or run /reload in pi.</li>
        </ol>
        <div class="mt-4 max-w-xl">
          <ul id="integrations" class="space-y-2">
            <li
              :for={row <- @integrations}
              id={"integration-#{row.agent}"}
              class="rounded-lg border border-base-200 px-3 py-2"
            >
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium">{row.label}</span>
                <span class="font-mono text-xs text-base-content/70">
                  <%= case row.cli do %>
                    <% {:ok, version} -> %>
                      {version}
                    <% :not_found -> %>
                      CLI not found
                  <% end %>
                </span>
                <span
                  id={"integration-state-#{row.agent}"}
                  class={[
                    "ml-auto text-xs font-medium",
                    row.state == :installed && "text-success",
                    row.state == :unreadable && "text-error"
                  ]}
                >
                  {integration_state_label(row.state)}
                </span>
              </div>
              <p
                :if={row.error}
                id={"integration-error-#{row.agent}"}
                class="mt-1 break-words text-xs text-error"
              >
                {row.error}
              </p>
              <p
                :if={row.state == :installed}
                id={"integration-activation-#{row.agent}"}
                class="mt-2 text-xs text-base-content/70"
              >
                <%= if row.agent == :pi do %>
                  Run /reload in pi, or restart it, to activate MCP tools and next-turn comments.
                <% else %>
                  Restart {row.label} to activate updated tools and hooks.
                <% end %>
              </p>
              <.form
                for={%{}}
                id={"integration-form-#{row.agent}"}
                phx-submit="install"
                class="mt-2"
              >
                <input type="hidden" name="agent" value={row.agent} />
                <fieldset
                  :for={sub <- row.subagents}
                  id={"subagent-#{row.agent}-#{sub.name}"}
                  class="mb-2 rounded-lg border border-base-300 p-2"
                >
                  <legend class="px-1 font-mono text-xs font-semibold">{sub.name}</legend>
                  <p class="text-xs text-base-content/70">{sub.description}</p>
                  <div class="mt-2 flex flex-wrap gap-3">
                    <div class="min-w-48 flex-1">
                      <label
                        for={"subagent-model-#{row.agent}-#{sub.name}"}
                        class="mb-1 block text-xs font-medium"
                      >
                        Model:
                      </label>
                      <input
                        id={"subagent-model-#{row.agent}-#{sub.name}"}
                        type="text"
                        name={"subagents[#{sub.name}][model]"}
                        value={sub.model}
                        autocomplete="off"
                        class="w-full rounded-lg border border-base-300 bg-base-100 px-2 py-1 font-mono text-sm"
                      />
                    </div>
                    <div>
                      <label
                        for={"subagent-effort-#{row.agent}-#{sub.name}"}
                        class="mb-1 block text-xs font-medium"
                      >
                        Effort:
                      </label>
                      <select
                        id={"subagent-effort-#{row.agent}-#{sub.name}"}
                        name={"subagents[#{sub.name}][effort]"}
                        class="min-h-8 rounded-lg border border-base-300 bg-base-100 px-2 py-1 text-sm"
                      >
                        <option value="" selected={sub.effort == ""}>Session's effort</option>
                        <option
                          :for={effort <- Subagents.efforts(row.agent)}
                          value={effort}
                          selected={sub.effort == effort}
                        >
                          {effort}
                        </option>
                      </select>
                    </div>
                  </div>
                  <p class="mt-2 text-xs text-base-content/70">
                    Empty fields keep the session's setting.
                  </p>
                </fieldset>
                <div class="flex gap-2">
                  <button
                    id={"install-#{row.agent}"}
                    type="submit"
                    disabled={row.cli == :not_found or row.state == :unreadable}
                    class="rounded-md bg-primary px-2.5 py-1 text-xs font-medium text-primary-content transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Install
                  </button>
                  <button
                    id={"uninstall-#{row.agent}"}
                    type="button"
                    phx-click="uninstall"
                    phx-value-agent={row.agent}
                    disabled={row.state in [:not_installed, :unreadable]}
                    class="rounded-md border border-base-300 px-2.5 py-1 text-xs font-medium transition hover:bg-base-200 disabled:cursor-not-allowed disabled:opacity-40"
                  >
                    Uninstall
                  </button>
                </div>
              </.form>
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
