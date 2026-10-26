defmodule Jarvis.DesignSkillTest do
  @moduledoc "The project-local skill `jarvis-design` keeps the shape agents rely on."
  use ExUnit.Case, async: true

  @dir Path.expand("../../.agents/skills/jarvis-design", __DIR__)
  @skill Path.join(@dir, "SKILL.md")

  defp frontmatter do
    [_, yaml, _] = @skill |> File.read!() |> String.split("---\n", parts: 3)

    for line <- String.split(yaml, "\n", trim: true), into: %{} do
      [key, value] = String.split(line, ": ", parts: 2)
      {key, value}
    end
  end

  test "name matches the directory and the description says when it applies" do
    %{"name" => name, "description" => description} = frontmatter()
    assert name == Path.basename(@dir)
    assert String.length(description) <= 1024

    for situation <- ["looks", "structured", "text"],
        do: assert(description =~ situation, "description does not mention #{situation}")
  end

  test "SKILL.md stays under 500 lines and has the shared rules, the layer order, and the review" do
    text = File.read!(@skill)
    assert text |> String.split("\n") |> length() < 500

    for heading <- [
          "## Shared rules",
          "### Floor (Grundnivå)",
          "### Task type parity",
          "## Layer 1: Diátaxis",
          "## Layer 2: COGA",
          "## Layer 3: Mayer",
          "## Layer 4: Display settings (Floe)",
          "## Review",
          "## UDL"
        ],
        do: assert(text =~ heading, "missing #{heading}")

    assert text =~ "never breaks a rule of an earlier layer or of the floor"
    assert text =~ "**met**" and text =~ "**not met**" and text =~ "**not checked**"
    assert text =~ "https://udlguidelines.cast.org/"
  end

  test "the skill is self-contained: every file it names exists, and it names no other skill" do
    text = File.read!(@skill)

    for [_, ref] <- Regex.scan(~r/`(references\/[^`]+)`/, text),
        do: assert(File.exists?(Path.join(@dir, ref)), "#{ref} is referenced but missing")

    refute text =~ ~r/requires? (the )?[\w-]+ skill/i
  end

  test "the checklist covers keyboard, focus, forms, motion, typography, color scheme, and responsiveness" do
    text = File.read!(Path.join(@dir, "references/checklist.md"))

    for heading <-
          ~w(Keyboard Focus Forms Motion Typography) ++ ["Color scheme", "Responsiveness"],
        do: assert(text =~ "## #{heading}", "checklist misses #{heading}")
  end

  test "AGENTS.md sends every board design decision to the skill" do
    assert File.read!(Path.expand("../../AGENTS.md", __DIR__)) =~ "`jarvis-design`"
  end
end
