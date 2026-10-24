defmodule Jarvis.Transcripts.Pi do
  @moduledoc """
  Reads pi session files (`~/.pi/agent/sessions/**.jsonl`), which hold a tree
  of entries; branches are shown in file order.
  """
  @behaviour Jarvis.Transcripts.Harness

  import Jarvis.Transcripts.Harness, only: [clip: 2, timestamp: 1]

  @impl true
  def read(%{"type" => "message", "message" => message} = entry) do
    at = timestamp(entry["timestamp"])

    case message["role"] do
      "user" ->
        %{role: :user, text: text(message["content"]), at: at}

      "assistant" ->
        blocks = List.wrap(message["content"])

        role =
          if Enum.any?(blocks, &match?(%{"type" => "text"}, &1)), do: :assistant, else: :tool_call

        %{role: role, text: assistant_text(blocks), at: at}

      "toolResult" ->
        %{
          role: :tool_result,
          text: clip("#{message["toolName"]}: #{text(message["content"])}", 2000),
          at: at
        }

      # The prompt and tool loadout: needed to resume, noise to read.
      "system" ->
        %{role: :meta, text: nil, at: at}

      _other ->
        %{role: :system, text: text(message["content"]), at: at}
    end
  end

  def read(%{"type" => "compaction"} = entry),
    do: %{
      role: :system,
      text: "Context compacted:\n\n" <> (entry["summary"] || ""),
      at: timestamp(entry["timestamp"])
    }

  def read(%{"type" => "branch_summary"} = entry),
    do: %{
      role: :system,
      text: "Branch summary:\n\n" <> (entry["summary"] || ""),
      at: timestamp(entry["timestamp"])
    }

  def read(%{"type" => "custom_message", "display" => true} = entry),
    do: %{role: :system, text: text(entry["content"]), at: timestamp(entry["timestamp"])}

  def read(%{"type" => "session_info", "name" => name} = entry) when is_binary(name),
    do: %{role: :meta, text: nil, at: timestamp(entry["timestamp"]), title: name}

  def read(entry), do: %{role: :meta, text: nil, at: timestamp(entry["timestamp"])}

  @impl true
  def resume_command(transcript),
    do: "cd #{shell(transcript.cwd)} && pi --session #{shell(transcript.path)}"

  defp assistant_text(blocks) do
    blocks
    |> Enum.flat_map(fn
      %{"type" => "text", "text" => text} ->
        [text]

      %{"type" => "toolCall", "name" => name} = call ->
        ["→ #{name} " <> clip(Jason.encode!(call["arguments"] || %{}), 400)]

      _thinking_or_other ->
        []
    end)
    |> Enum.join("\n\n")
  end

  defp text(content) when is_binary(content), do: content

  defp text(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"type" => "text", "text" => text} -> text
      %{"type" => "image"} -> "[image]"
      _ -> ""
    end)
  end

  defp text(_), do: nil

  defp shell(path), do: "'" <> String.replace(path, "'", ~S('\'')) <> "'"
end
