defmodule Jarvis.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      JarvisWeb.Telemetry,
      Jarvis.Repo,
      {DNSCluster, query: Application.get_env(:jarvis, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Jarvis.PubSub},
      # Start a worker by calling: Jarvis.Worker.start_link(arg)
      # {Jarvis.Worker, arg},
      # Start to serve requests, typically the last entry
      JarvisWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Jarvis.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JarvisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
