defmodule JarvisWeb.Api.AgentScope do
  @moduledoc """
  Resolves the calling agent from the `x-jarvis-cwd`, `x-jarvis-session`, and
  `x-jarvis-session-name`, and `x-jarvis-agent` (pi when absent) headers and assigns
  `current_scope`. Header values are URI-encoded so any path survives.

  Every request also counts as the session's heartbeat.
  """
  import Plug.Conn

  alias Jarvis.Workspaces

  @headers %{
    "x-jarvis-cwd" => "cwd",
    "x-jarvis-session" => "session_id",
    "x-jarvis-session-name" => "session_name",
    "x-jarvis-agent" => "agent"
  }

  def init(opts), do: opts

  def call(conn, _opts) do
    params =
      for {header, key} <- @headers,
          value = List.first(get_req_header(conn, header)),
          into: %{} do
        {key, URI.decode(value)}
      end

    case Workspaces.register(params) do
      {:ok, scope} ->
        assign(conn, :current_scope, scope)

      {:error, reason} ->
        details =
          case reason do
            %Ecto.Changeset{} = changeset -> JarvisWeb.Api.FallbackController.errors(changeset)
            :invalid_cwd -> %{cwd: ["must be an existing absolute directory"]}
          end

        conn
        |> put_status(:bad_request)
        |> Phoenix.Controller.json(%{
          error: "missing or invalid x-jarvis-* identity headers",
          details: details
        })
        |> halt()
    end
  end
end
