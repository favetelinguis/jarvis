defmodule JarvisWeb.Api.FallbackController do
  use JarvisWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{error: "not found in this project"})
  end

  def call(conn, {:error, {:widgets, messages}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid widgets; nothing was changed", details: %{widgets: messages}})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid", details: errors(changeset)})
  end

  @doc "Changeset errors as `%{field => [message]}`."
  def errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
