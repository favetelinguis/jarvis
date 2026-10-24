defmodule JarvisWeb.Api.PlanningController do
  @moduledoc """
  The agent-facing API. Responses carry `text`, a markdown rendering for the
  model, and `url`, the page where the human sees the same thing live.
  """
  use JarvisWeb, :controller

  alias Jarvis.{Planning, Workspaces}
  alias Jarvis.Planning.Markdown

  action_fallback JarvisWeb.Api.FallbackController

  def overview(conn, _params) do
    scope = conn.assigns.current_scope
    goals = Planning.list_goals(scope)
    sessions = Workspaces.list_sessions(scope.project)
    reply(conn, Markdown.overview(scope.project, goals, sessions), ~p"/projects/#{scope.project}")
  end

  def show_goal(conn, %{"goal" => goal}) do
    with {:ok, goal} <- Planning.fetch_goal(conn.assigns.current_scope, int(goal)) do
      reply(conn, Markdown.goal(goal, Planning.list_widgets(goal, nil)), goal_path(goal), %{
        goal: goal.number
      })
    end
  end

  def create_goal(conn, params) do
    with {:ok, goal} <- Planning.create_goal(conn.assigns.current_scope, params) do
      conn |> put_status(:created) |> show_goal(%{"goal" => goal.number})
    end
  end

  def update_goal(conn, %{"goal" => number} = params) do
    scope = conn.assigns.current_scope

    with {:ok, goal} <- Planning.fetch_goal(scope, int(number)),
         {:ok, _} <- Planning.update_goal(scope, goal, Map.delete(params, "goal")) do
      show_goal(conn, %{"goal" => number})
    end
  end

  def show_task(conn, %{"goal" => goal, "task" => task}) do
    with {:ok, task} <- Planning.fetch_task(conn.assigns.current_scope, int(goal), int(task)) do
      widgets = Planning.list_widgets(task.goal, task)

      reply(conn, Markdown.task(task, widgets), task_path(task), %{
        goal: task.goal.number,
        task: task.number
      })
    end
  end

  def catalog(conn, _params), do: reply(conn, Markdown.catalog(), ~p"/design-system")

  def widgets(conn, %{"goal" => goal_number, "ops" => ops} = params) do
    scope = conn.assigns.current_scope

    with {:ok, goal} <- Planning.fetch_goal(scope, int(goal_number)),
         {:ok, task} <- fetch_optional_task(scope, goal, params["task"]),
         {:ok, _ids} <- Planning.apply_widget_ops(scope, goal, task, ops) do
      if task,
        do: show_task(conn, %{"goal" => goal_number, "task" => task.number}),
        else: show_goal(conn, %{"goal" => goal_number})
    end
  end

  def widgets(_conn, _params), do: {:error, {:widgets, ["ops: required"]}}

  def create_task(conn, %{"goal" => number} = params) do
    scope = conn.assigns.current_scope

    with {:ok, goal} <- Planning.fetch_goal(scope, int(number)),
         {:ok, task} <- Planning.create_task(scope, goal, Map.delete(params, "goal")) do
      conn |> put_status(:created) |> show_task(%{"goal" => number, "task" => task.number})
    end
  end

  def update_task(conn, %{"goal" => goal, "task" => number} = params) do
    scope = conn.assigns.current_scope

    with {:ok, task} <- Planning.fetch_task(scope, int(goal), int(number)),
         {:ok, _} <- Planning.update_task(scope, task, Map.drop(params, ["goal", "task"])) do
      show_task(conn, %{"goal" => goal, "task" => number})
    end
  end

  def create_comment(conn, %{"goal" => goal_number} = params) do
    scope = conn.assigns.current_scope

    with {:ok, goal} <- Planning.fetch_goal(scope, int(goal_number)),
         {:ok, task} <- fetch_optional_task(scope, goal, params["task"]),
         {:ok, _} <- Planning.add_comment(scope, goal, task, params) do
      if task,
        do: show_task(conn, %{"goal" => goal_number, "task" => task.number}),
        else: show_goal(conn, %{"goal" => goal_number})
    end
  end

  @states %{"idle" => :idle, "working" => :working, "ended" => :ended}

  def update_session(conn, params) do
    case Map.fetch(@states, params["state"]) do
      {:ok, state} ->
        Workspaces.set_state(conn.assigns.current_scope, state)
        json(conn, %{ok: true})

      :error ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "state must be idle, working, or ended"})
    end
  end

  def wake(conn, _params) do
    case Planning.take_wake(conn.assigns.current_scope) do
      {:ok, []} -> json(conn, %{count: 0, text: nil})
      {:ok, comments} -> json(conn, %{count: length(comments), text: Markdown.wake(comments)})
    end
  end

  def inbox(conn, _params) do
    case Planning.take_inbox(conn.assigns.current_scope) do
      {:ok, []} -> json(conn, %{count: 0, text: nil})
      {:ok, comments} -> json(conn, %{count: length(comments), text: Markdown.inbox(comments)})
    end
  end

  defp fetch_optional_task(_scope, _goal, nil), do: {:ok, nil}

  defp fetch_optional_task(scope, goal, number) do
    Planning.fetch_task(scope, goal.number, int(number))
  end

  defp reply(conn, text, path, extra \\ %{}) do
    json(conn, Map.merge(extra, %{text: text, url: JarvisWeb.Endpoint.url() <> path}))
  end

  defp goal_path(goal), do: ~p"/projects/#{goal.project_id}/goals/#{goal.number}"

  defp task_path(task),
    do: ~p"/projects/#{task.project_id}/goals/#{task.goal.number}/tasks/#{task.number}"

  # Route segments and JSON numbers both arrive here; anything else is "not found".
  defp int(n) when is_integer(n), do: n

  defp int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, ""} -> i
      _ -> -1
    end
  end

  defp int(_), do: -1
end
