defmodule Jarvis.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    with {:error, message} <- startup_check() do
      IO.puts(:stderr, "jarvis: " <> message)
      System.halt(1)
    end

    put_secret_key_base()

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

  # A Release has no secret in its environment: it keeps one in the Data directory.
  defp put_secret_key_base do
    endpoint = Application.get_env(:jarvis, JarvisWeb.Endpoint, [])

    if is_nil(endpoint[:secret_key_base]) do
      Application.put_env(
        :jarvis,
        JarvisWeb.Endpoint,
        Keyword.put(endpoint, :secret_key_base, Jarvis.DataDir.secret_key_base())
      )
    end
  end

  defp startup_check do
    with :ok <- Jarvis.DataDir.prepare(), do: check_port()
  end

  # Bandit's own failure is a crash dump; say which port and why instead.
  defp check_port do
    endpoint = Application.get_env(:jarvis, JarvisWeb.Endpoint, [])
    http = endpoint[:http] || []
    port = http[:port]

    with true <- endpoint[:server] == true and is_integer(port),
         {:error, reason} <-
           :gen_tcp.listen(port, ip: http[:ip] || {127, 0, 0, 1}, reuseaddr: true) do
      {:error, "cannot serve on port #{port}: #{:inet.format_error(reason)}"}
    else
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      _ ->
        :ok
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    JarvisWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
