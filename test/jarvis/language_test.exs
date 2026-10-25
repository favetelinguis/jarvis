defmodule Jarvis.LanguageTest do
  use Jarvis.DataCase, async: false

  alias Jarvis.Language

  test "Swedish by default, then the saved choice; unknown codes are refused" do
    assert Language.current() == "sv"
    assert Language.line() == "Language: Svenska"
    assert {:ok, "en"} = Language.save("en")
    assert Language.line() == "Language: English"
    assert {:error, :unknown_language} = Language.save("fr")
    assert Language.current() == "en"
  end

  test "every workflow skill names the board language" do
    for path <- Path.wildcard("skills/*/SKILL.md") do
      assert File.read!(path) =~ "**Board language:**", path
    end
  end
end
