defmodule JarvisWeb.WidgetEvents do
  @moduledoc """
  The `widget:*` events of every page that shows widgets: opening the comment
  composer, posting comments, and acting on widgets (confirm, answer, weigh,
  mark), plus the ephemeral view state (a tour step, a selected example).

  A page assigns `:scope`, `:widgets`, `:ui`, `:composer`, and `:goal` (and
  `:task` on a task page). On the design-system page `:sandbox?` is true and
  everything happens in memory, so the human can play without touching a board.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Jarvis.Planning
  alias Jarvis.Planning.{Catalog, Comment}

  @doc "Handles one `widget:*` event; returns `{:noreply, socket}`."
  def handle("widget:compose", %{"widget" => id} = params, socket) do
    part = if params["part"] in [nil, ""], do: nil, else: params["part"]
    {:noreply, assign(socket, :composer, %{widget: to_int(id), part: part})}
  end

  def handle("widget:cancel", _params, socket), do: {:noreply, assign(socket, :composer, nil)}

  def handle("widget:seen", %{"widget" => id}, socket) do
    id = to_int(id)
    seen = socket.assigns |> Map.get(:seen, MapSet.new()) |> MapSet.put(id)

    {:noreply,
     socket |> assign(:changed, MapSet.delete(socket.assigns.changed, id)) |> assign(:seen, seen)}
  end

  def handle(
        "widget:comment",
        %{"body" => body},
        %{assigns: %{composer: %{} = composer}} = socket
      ) do
    if String.trim(body) == "" do
      {:noreply, socket}
    else
      post_comment(socket, composer, body)
    end
  end

  def handle("widget:comment", _params, socket), do: {:noreply, socket}

  def handle("widget:ui", %{"widget" => id, "key" => key, "value" => value}, socket),
    do: {:noreply, put_ui(socket, to_int(id), key, value)}

  def handle("widget:select", %{"widget" => id} = params, socket),
    do: {:noreply, put_ui(socket, to_int(id), "sel", params["sel"] || %{})}

  def handle("widget:select_clear", %{"widget" => id}, socket),
    do: {:noreply, put_ui(socket, to_int(id), "sel", %{})}

  def handle("widget:action", %{"widget" => id, "action" => action} = params, socket),
    do: act(socket, to_int(id), action, params)

  def handle("widget:answer", %{"widget" => id} = params, socket),
    do: act(socket, to_int(id), "answer", params)

  def handle("widget:weights", %{"widget" => id, "w" => weights}, socket) do
    widget_id = to_int(id)
    widget = find(socket, widget_id)
    current = if widget, do: widget.human["weights"] || %{}, else: %{}

    changed =
      for {criterion, value} <- weights,
          widget != nil,
          effective(widget, current, criterion) != to_string(value),
          do: {criterion, value}

    Enum.reduce(changed, {:noreply, socket}, fn {criterion, value}, {:noreply, socket} ->
      act(socket, widget_id, "weight", %{"criterion" => criterion, "value" => value})
    end)
  end

  def handle("widget:render_error", %{"widget" => id, "message" => message}, socket),
    do: act(socket, to_int(id), "render_error", %{"message" => message})

  def handle("widget:rendered", %{"widget" => id}, socket),
    do: act(socket, to_int(id), "rendered", %{})

  @doc """
  Assigns `widgets` and adds to `:changed` every widget an agent added or
  rewrote since the page last loaded. The human's own actions only touch
  `human`, so they never mark a widget. Marks stay until the human reads them
  (`widget:seen`).
  """
  def assign_widgets(socket, widgets) do
    changed = Map.get(socket.assigns, :changed, MapSet.new())

    changed =
      case Map.get(socket.assigns, :widgets) do
        nil ->
          changed

        previous ->
          before = Map.new(previous, &{&1.id, {&1.kind, &1.data}})

          for w <- widgets, Map.get(before, w.id) != {w.kind, w.data}, into: changed, do: w.id
      end

    socket |> assign(:widgets, widgets) |> assign(:changed, changed)
  end

  @doc """
  The widgets to mark as changed: those changed since the page loaded, and
  those an unread turn report changed, except the ones the human marked read.
  """
  def changed(assigns, reports) do
    reports
    |> Enum.flat_map(&Jarvis.Planning.Report.widget_ids/1)
    |> MapSet.new()
    |> MapSet.difference(Map.get(assigns, :seen, MapSet.new()))
    |> MapSet.union(assigns.changed)
  end

  defp effective(widget, current, criterion) do
    default =
      Enum.find_value(widget.data["criteria"], fn c -> c["id"] == criterion && c["weight"] end)

    to_string(Map.get(current, criterion, default))
  end

  defp put_ui(socket, id, key, value) do
    ui = socket.assigns.ui
    state = Map.get(ui, id, %{})
    state = if value in [nil, ""], do: Map.delete(state, key), else: Map.put(state, key, value)
    assign(socket, :ui, Map.put(ui, id, state))
  end

  defp find(socket, id), do: Enum.find(socket.assigns.widgets, &(&1.id == id))

  ## Real boards

  defp post_comment(%{assigns: %{sandbox?: true}} = socket, composer, body) do
    widget = find(socket, composer.widget)
    comment = sandbox_comment(widget, composer.part, :human, body)
    send(self(), {:sandbox_reply, comment})
    {:noreply, socket |> add_sandbox_comment(comment) |> assign(:composer, nil)}
  end

  defp post_comment(socket, composer, body) do
    %{scope: scope, goal: goal} = socket.assigns
    task = Map.get(socket.assigns, :task)

    attrs = %{"body" => body, "widget" => composer.widget, "part" => composer.part}

    case Planning.add_comment(scope, goal, task, attrs) do
      {:ok, _} ->
        {:noreply, assign(socket, :composer, nil)}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Could not post the comment.")}
    end
  end

  defp act(%{assigns: %{sandbox?: true}} = socket, id, action, params) do
    widget = find(socket, id)

    case widget && Catalog.human_action(widget, action, params) do
      {:ok, human, notes} ->
        widgets =
          Enum.map(socket.assigns.widgets, &if(&1.id == id, do: %{&1 | human: human}, else: &1))

        widget = %{widget | human: human}

        socket =
          Enum.reduce(notes, assign(socket, :widgets, widgets), fn {part, message}, socket ->
            comment = sandbox_comment(widget, part, :human, message)
            send(self(), {:sandbox_judge, widget.id, comment})
            add_sandbox_comment(socket, %{comment | deliver: false})
          end)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  defp act(socket, id, action, params) do
    # Read the widget afresh: several actions of one event (re-weighing) build on each other.
    with {:ok, widget} <- Planning.fetch_widget(socket.assigns.scope, id),
         {:ok, _} <- Planning.widget_action(socket.assigns.scope, widget, action, params) do
      {:noreply, socket}
    else
      _ -> {:noreply, Phoenix.LiveView.put_flash(socket, :error, "That did not work.")}
    end
  end

  ## Sandbox

  @doc "A comment that exists only in memory, for the design-system page."
  def sandbox_comment(widget, part, author, body) do
    %Comment{
      id: -System.unique_integer([:positive]),
      author: author,
      body: body,
      widget_id: widget.id,
      part: part,
      anchor_label: Planning.anchor_label(widget, part),
      anchor_text: nil,
      deliver: author == :human,
      inserted_at: DateTime.utc_now()
    }
  end

  def add_sandbox_comment(socket, comment),
    do: assign(socket, :comments, socket.assigns.comments ++ [comment])

  defp to_int(n) when is_integer(n), do: n
  defp to_int(n) when is_binary(n), do: String.to_integer(n)
end
