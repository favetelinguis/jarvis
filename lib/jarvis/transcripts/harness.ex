defmodule Jarvis.Transcripts.Harness do
  @moduledoc """
  What Jarvis must know about one agent harness's session files: how to read
  a decoded line in harness-neutral terms, and how to resume a session.
  """

  alias Jarvis.Transcripts.Transcript

  @typedoc """
  The reading of one line. `:title` is set by lines that name the session
  explicitly; otherwise the first user message becomes the title.
  """
  @type entry :: %{
          required(:role) => atom(),
          required(:text) => String.t() | nil,
          required(:at) => DateTime.t() | nil,
          optional(:title) => String.t()
        }

  @callback read(decoded :: map()) :: entry
  @callback resume_command(Transcript.t()) :: String.t()

  @doc "The module for a harness."
  def for(:pi), do: Jarvis.Transcripts.Pi
  def for(:codex), do: Jarvis.Transcripts.Codex

  @doc "Shortens long tool payloads for display; the exact bytes stay in the line."
  def clip(nil, _max), do: nil
  def clip(text, max) when byte_size(text) <= max, do: text
  def clip(text, max), do: String.slice(text, 0, max) <> "\n… (truncated)"

  @doc "Parses an ISO 8601 timestamp, or a Unix timestamp in milliseconds."
  def timestamp(ms) when is_integer(ms), do: ms |> DateTime.from_unix!(:millisecond) |> usec()

  def timestamp(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _} -> usec(at)
      _ -> nil
    end
  end

  def timestamp(_), do: nil

  defp usec(%DateTime{microsecond: {us, _}} = at), do: %{at | microsecond: {us, 6}}
end
