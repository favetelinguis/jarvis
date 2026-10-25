defmodule Jarvis.Language do
  @moduledoc """
  The board language: the language agents write goals, tasks, widgets, and
  comments in. One per Jarvis install, set on the settings page; Swedish until
  the human changes it. Agents learn it from the first line of `jarvis_read`.
  """

  alias Jarvis.{Repo, Setting}

  @key "language"
  @languages %{"sv" => "Svenska", "en" => "English"}

  @doc "The selectable languages as `[{code, name}]`."
  def all, do: Enum.sort(@languages)

  @doc "The saved language code, `\"sv\"` by default."
  def current do
    case Repo.get(Setting, @key) do
      %Setting{value: %{"code" => code}} when is_map_key(@languages, code) -> code
      _ -> "sv"
    end
  end

  def name(code \\ nil), do: Map.fetch!(@languages, code || current())

  @doc "Saves the language; leaves existing content alone."
  def save(code) when is_map_key(@languages, code) do
    Repo.insert!(%Setting{key: @key, value: %{"code" => code}},
      on_conflict: {:replace, [:value, :updated_at]},
      conflict_target: :key
    )

    {:ok, code}
  end

  def save(_), do: {:error, :unknown_language}

  @doc "The first line of every `jarvis_read` answer."
  def line, do: "Language: #{name()}"
end
