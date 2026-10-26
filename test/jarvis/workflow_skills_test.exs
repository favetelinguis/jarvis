defmodule Jarvis.WorkflowSkillsTest do
  @moduledoc "The workflow skills share one list of board rules and name the transitions they own."
  use ExUnit.Case, async: true

  alias Jarvis.Planning.TaskType

  @skills Path.expand("../../skills", __DIR__)
  @workflows ~w(specify design design-review impl impl-review research pr-review learn)

  defp skill(name), do: File.read!(Path.join([@skills, name, "SKILL.md"]))

  defp owned(name) do
    [_, rest] = String.split(skill(name), "### Transitions this workflow owns\n", parts: 2)
    rest |> String.split("\n## ", parts: 2) |> hd()
  end

  test "every workflow skill carries the canonical board rules word for word" do
    rules = Path.join(@skills, "board-rules.md") |> File.read!() |> String.trim_trailing()

    for name <- @workflows do
      assert [_, block] = String.split(skill(name), "<!-- board-rules -->\n", parts: 2),
             "#{name} has no board rules"

      [copy | _] = String.split(block, "\n<!-- /board-rules -->", parts: 2)
      assert copy == rules, "the board rules in #{name} differ from skills/board-rules.md"
    end
  end

  test "the board rules are numbered MUST and MUST NOT sentences" do
    rules = Path.join(@skills, "board-rules.md") |> File.read!()
    items = Regex.scan(~r/^(\d+)\. (.*)$/m, rules)
    assert length(items) >= 10

    for {[_, n, text], i} <- Enum.with_index(items, 1) do
      assert String.to_integer(n) == i

      assert text =~ ~r/^MUST (NOT )?[a-z]/,
             "rule #{n} does not start with MUST or MUST NOT and a verb"
    end
  end

  test "the rules ask for a reason that names the interview question it records" do
    rules = Path.join(@skills, "board-rules.md") |> File.read!()
    assert rules =~ "MUST give `reason`"
    assert rules =~ "`Q3 → R2 reworded`"
  end

  test "each workflow lists every agent transition and handoff of its command" do
    for {type, _} <- TaskType.all(), t <- TaskType.transitions(type), t.mover == :agent do
      name = String.trim_leading(t.command, "/")
      assert owned(name) =~ ~s("#{t.name}"), "#{name} does not list #{t.name}"
    end

    for type <- TaskType.keys(), step <- TaskType.handoff_steps(type) do
      {:agent, command, true} = TaskType.start_turn(type, step)
      name = String.trim_leading(command, "/")
      label = TaskType.step_label(type, step)
      assert owned(name) =~ "Hand over #{label}", "#{name} does not list the handoff of #{label}"
    end
  end

  test "design-review and impl-review leave the board and the step unchanged" do
    for name <- ~w(design-review impl-review) do
      text = skill(name)
      assert owned(name) =~ "None. This workflow is a read-only check"
      refute text =~ ~s(`transition: "), "#{name} still moves the task"
    end
  end

  test "no workflow tells the agent to make a transition the human makes" do
    human =
      for {type, _} <- TaskType.all(),
          t <- TaskType.transitions(type),
          t.mover == :human,
          do: t.name

    for name <- @workflows, t <- Enum.uniq(human) do
      refute skill(name) =~ ~s(transition: "#{t}"), "#{name} makes the human's #{t}"
    end
  end

  test "design and impl review in a fresh context and impl records evidence before handing over" do
    for name <- ~w(design impl) do
      text = skill(name)
      assert text =~ "fresh context", "#{name} runs no review in a fresh context"
      assert text =~ "`findings` widget in the section Review"
    end

    assert skill("impl") =~ "one `evidence` widget in the section Evidence"
  end

  test "learn links every check question to the explanation it tests" do
    assert skill("learn") =~
             "Link every question to the explanation widget it tests with `explains`"
  end

  test "pr-review matches the human's view without changing it" do
    text = skill("pr-review")
    assert text =~ "write one `view_matches` widget in **picture**"
    assert text =~ "Never change my concerns"
  end

  test "poc moves a Feature through steps that exist, in lifecycle order" do
    [sentence] = Regex.run(~r/^- Claim each task.*$/m, skill("poc"))
    [_, path] = String.split(sentence, "):", parts: 2)
    named = Regex.scan(~r/([A-Z][a-z]+) (?:when|while)/, path) |> Enum.map(&List.last/1)

    later = :feature |> TaskType.steps() |> tl() |> Enum.map(&elem(&1, 1))
    assert named == later
  end

  test "a pasted report a skill expects is one /impl-review still writes" do
    headings = Regex.scan(~r/^(## .+)$/m, skill("impl-review")) |> Enum.map(&List.last/1)

    for name <- @workflows ++ ["poc"],
        [_, heading] <- Regex.scan(~r/starts with `(## [^`]+)`/, skill(name)) do
      assert Enum.any?(
               headings,
               &String.starts_with?(&1, String.replace(heading, ~r/ N\.M$/, ""))
             ),
             "#{name} expects #{inspect(heading)}, which /impl-review no longer writes"
    end
  end
end
