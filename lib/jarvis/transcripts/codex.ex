defmodule Jarvis.Transcripts.Codex do
  @moduledoc """
  Reads Codex rollout files (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`).

  The user's own words come from `user_message` events; user and developer
  response items also carry injected context (AGENTS.md, environment), so they
  are kept for resuming but not shown.
  """
  @behaviour Jarvis.Transcripts.Harness

  import Jarvis.Transcripts.Harness, only: [clip: 2, timestamp: 1]

  @impl true
  def read(%{"type" => type, "payload" => payload} = line) when is_map(payload) do
    entry(type, payload) |> Map.put(:at, timestamp(line["timestamp"]))
  end

  def read(line), do: %{role: :meta, text: nil, at: timestamp(line["timestamp"])}

  defp entry("event_msg", %{"type" => "user_message", "message" => message}),
    do: %{role: :user, text: message}

  defp entry("response_item", %{"type" => "message", "role" => "assistant", "content" => content}),
       do: %{role: :assistant, text: text(content)}

  defp entry("response_item", %{"type" => type, "name" => name} = call)
       when type in ["function_call", "custom_tool_call"] do
    args = call["arguments"] || call["input"] || ""
    args = if is_binary(args), do: args, else: Jason.encode!(args)
    %{role: :tool_call, text: "→ #{name} " <> clip(args, 400)}
  end

  defp entry("response_item", %{"type" => type} = result)
       when type in ["function_call_output", "custom_tool_call_output"] do
    %{role: :tool_result, text: clip(output(result["output"]), 2000)}
  end

  defp entry("compacted", payload),
    do: %{role: :system, text: "Context compacted:\n\n" <> (payload["message"] || "")}

  defp entry(_type, _payload), do: %{role: :meta, text: nil}

  @impl true
  def resume_command(transcript),
    do: "cd #{shell(transcript.cwd)} && codex resume #{transcript.external_id}"

  defp text(content) when is_list(content) do
    Enum.map_join(content, "\n", fn
      %{"text" => text} -> text
      _ -> ""
    end)
  end

  defp text(_), do: nil

  defp output(output) when is_binary(output), do: output
  defp output(%{"content" => content}), do: output(content)
  defp output(list) when is_list(list), do: text(list)
  defp output(other), do: Jason.encode!(other)

  defp shell(path), do: "'" <> String.replace(path, "'", ~S('\'')) <> "'"
end
