defmodule JarvisWeb.SettingsLive do
  @moduledoc """
  The brand colors. Three colors drive the whole theme; the page previews
  unsaved colors on sample widgets and shows the contrast of every text color.
  """
  use JarvisWeb, :live_view

  alias Jarvis.{Integrations, Planning.Catalog, Theme}

  import JarvisWeb.WidgetComponents

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
  def handle_event("install", %{"agent" => agent}, socket),
    do: {:noreply, change_integration(socket, agent, &Integrations.install/1)}

  def handle_event("uninstall", %{"agent" => agent}, socket),
    do: {:noreply, change_integration(socket, agent, &Integrations.uninstall/1)}

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
    <Layouts.app flash={@flash} theme_css={@theme_css} crumbs={[{"Settings", ~p"/settings"}]}>
      <h1 class="text-2xl font-semibold tracking-tight">Brand colors</h1>
      <p class="mt-1 max-w-2xl text-sm text-base-content/70">
        Three colors drive every widget, button, and graph in Jarvis. Change them to match the company you work for;
        the rest of the palette is derived, and text is always kept at a contrast of at least 4.5:1.
      </p>

      <div class="mt-6 grid gap-6 lg:grid-cols-[22rem_minmax(0,1fr)]">
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
            >Save</button>
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
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
              Preview (not saved until you press Save)
            </p>
            <.widget :for={w <- @samples} w={w} ctx={@ctx} />
          </div>

          <div class="rounded-2xl border border-base-300 bg-base-100 p-4">
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
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
      <section id="integrations-panel" class="mt-10">
        <h2 class="text-xl font-semibold tracking-tight">Integrations</h2>
        <p class="mt-1 max-w-2xl text-sm text-base-content/70">
          Install Jarvis into your coding agents. It changes only their user-level configuration, for every project.
        </p>
        <div class="mt-4 max-w-xl">
          <ul id="integrations" class="space-y-2">
            <li
              :for={row <- @integrations}
              id={"integration-#{row.agent}"}
              class="rounded-lg border border-base-200 px-3 py-2"
            >
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium">{row.label}</span>
                <span class="font-mono text-xs text-base-content/50">
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
              <div class="mt-2 flex gap-2">
                <button
                  id={"install-#{row.agent}"}
                  type="button"
                  phx-click="install"
                  phx-value-agent={row.agent}
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
            </li>
          </ul>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
