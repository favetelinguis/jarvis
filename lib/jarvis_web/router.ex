defmodule JarvisWeb.Router do
  use JarvisWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {JarvisWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug JarvisWeb.Api.AgentScope
  end

  scope "/", JarvisWeb do
    pipe_through :browser

    live_session :default do
      live "/", ProjectsLive
      live "/projects/:project", ProjectLive
      live "/projects/:project/goals/:goal", GoalLive
      live "/projects/:project/goals/:goal/tasks/:task", TaskLive
      live "/transcripts/:id", TranscriptLive
    end
  end

  pipeline :hook do
    plug :accepts, ["json"]
  end

  # Called by harness hooks, which know a session file but not the Jarvis identity headers.
  scope "/api", JarvisWeb.Api do
    pipe_through :hook

    post "/transcripts/sync", TranscriptController, :sync
  end

  scope "/api", JarvisWeb.Api do
    pipe_through :api

    get "/transcripts", TranscriptController, :index
    post "/transcripts/:id/restore", TranscriptController, :restore

    get "/overview", PlanningController, :overview
    post "/goals", PlanningController, :create_goal
    get "/goals/:goal", PlanningController, :show_goal
    patch "/goals/:goal", PlanningController, :update_goal
    post "/goals/:goal/tasks", PlanningController, :create_task
    get "/goals/:goal/tasks/:task", PlanningController, :show_task
    patch "/goals/:goal/tasks/:task", PlanningController, :update_task
    post "/goals/:goal/comments", PlanningController, :create_comment
    put "/session", PlanningController, :update_session
    post "/inbox", PlanningController, :inbox
  end
end
