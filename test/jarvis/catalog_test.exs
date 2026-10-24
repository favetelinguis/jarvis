defmodule Jarvis.CatalogTest do
  use ExUnit.Case, async: true

  alias Jarvis.Planning.Catalog

  describe "examples" do
    for kind <- Catalog.kinds() do
      test "the #{kind} example is valid and has parts that resolve" do
        kind = unquote(kind)
        assert {:ok, data} = Catalog.validate(kind, Catalog.example(kind))
        widget = %{id: 1, kind: kind, data: data, human: %{}}

        for {part, label, _text} <- Catalog.parts(widget) do
          assert {^label, _} = Catalog.part(widget, part)
        end

        assert Catalog.text(widget) =~ "W1 · #{kind}"
      end
    end
  end

  describe "validate/2" do
    test "names every invalid field" do
      assert {:error, errors} =
               Catalog.validate("requirement", %{"pattern" => "sometimes", "id" => "R1"})

      assert "pattern: must be one of ubiquitous, event, state, unwanted, optional" in errors
      assert "system: required" in errors
      assert "response: required" in errors
    end

    test "rejects unknown fields" do
      assert {:error, [error]} = Catalog.validate("prose", %{"text" => "x", "txt" => "y"})
      assert error =~ "txt: unknown field"
    end

    test "requires a trigger unless the requirement is ubiquitous" do
      data = %{"id" => "R1", "pattern" => "event", "system" => "board", "response" => "act"}

      assert {:error, ["trigger: required for the event pattern"]} =
               Catalog.validate("requirement", data)

      assert {:ok, _} = Catalog.validate("requirement", Map.put(data, "trigger", "x happens"))
    end

    test "fills in ids of list items the agent left out and keeps the ones it gave" do
      {:ok, data} =
        Catalog.validate("examples", %{
          "columns" => ["a"],
          "rows" => [
            %{"values" => ["1"], "expected" => "x"},
            %{"id" => "mine", "values" => ["2"], "expected" => "y"}
          ]
        })

      assert Enum.map(data["rows"], & &1["id"]) == ["row1", "mine"]
    end

    test "rejects duplicate ids" do
      rows = [
        %{"id" => "x", "values" => ["1"], "expected" => "y"},
        %{"id" => "x", "values" => ["2"], "expected" => "y"}
      ]

      assert {:error, [error]} =
               Catalog.validate("examples", %{"columns" => ["a"], "rows" => rows})

      assert error =~ "id \"x\" is used twice"
    end

    test "rejects rows that do not fit the columns" do
      rows = [%{"values" => ["1"], "expected" => "y"}]

      assert {:error, [error]} =
               Catalog.validate("examples", %{"columns" => ["a", "b"], "rows" => rows})

      assert error =~ "needs 2 value(s)"
    end

    test "checks references inside an architecture graph" do
      data = %{
        "nodes" => [%{"id" => "a", "label" => "A", "kind" => "service"}],
        "edges" => [%{"from" => "a", "to" => "zzz"}]
      }

      assert {:error, [error]} = Catalog.validate("architecture", data)
      assert error =~ "no node \"zzz\""
    end

    test "a gate quiz must name its transition and every question needs a correct answer" do
      quiz = %{
        "mode" => "gate",
        "questions" => [
          %{
            "id" => "q",
            "prompt" => "?",
            "type" => "single",
            "options" => [
              %{"id" => "a", "text" => "x", "explanation" => "e"},
              %{"id" => "b", "text" => "y", "explanation" => "e"}
            ]
          }
        ]
      }

      assert {:error, errors} = Catalog.validate("quiz", quiz)
      assert "gates: required in gate mode" in errors
      assert Enum.any?(errors, &(&1 =~ "exactly one must be correct"))
    end

    test "comparison scores stay between 0 and 5" do
      data = %{
        "criteria" => [%{"id" => "c", "label" => "C", "weight" => 6}],
        "options" => [%{"id" => "o", "label" => "O", "scores" => %{"c" => 9}}]
      }

      assert {:error, errors} = Catalog.validate("comparison", data)
      assert Enum.any?(errors, &(&1 =~ "weight: must be a whole number from 0 to 5"))
      assert Enum.any?(errors, &(&1 =~ "scores.c"))
    end
  end

  describe "requirement" do
    setup do
      {:ok, data} = Catalog.validate("requirement", Catalog.example("requirement"))
      %{widget: %{kind: "requirement", data: data, human: %{}}}
    end

    test "confirming and changing the text", %{widget: widget} do
      assert {:ok, %{"confirmed" => true} = human, []} =
               Catalog.human_action(widget, "confirm", %{})

      assert Catalog.body_text(%{widget | human: human}) =~ "confirmed"

      changed = Map.put(widget.data, "response", "do something else")
      assert Catalog.reconcile("requirement", widget.data, changed, human) == %{}
    end

    test "moving or editing nothing relevant keeps the confirmation", %{widget: widget} do
      human = %{"confirmed" => true}
      assert Catalog.reconcile("requirement", widget.data, widget.data, human) == human
    end

    test "renders one EARS sentence", %{widget: widget} do
      assert Catalog.requirement_sentence(widget.data) ==
               "When the human clicks Confirm on a requirement card, the board shall show the requirement as confirmed."
    end
  end

  describe "comparison ranking" do
    setup do
      data = %{
        "criteria" => [
          %{"id" => "speed", "label" => "Speed", "weight" => 3},
          %{"id" => "cost", "label" => "Cost", "weight" => 1}
        ],
        "options" => [
          %{"id" => "a", "label" => "A", "scores" => %{"speed" => 5, "cost" => 1}},
          %{"id" => "b", "label" => "B", "scores" => %{"speed" => 2, "cost" => 5}}
        ]
      }

      %{data: data}
    end

    test "ranks by score times weight", %{data: data} do
      assert [{%{"id" => "a"}, 16}, {%{"id" => "b"}, 11}] = Catalog.ranking(data, %{})

      assert [{%{"id" => "b"}, 17}, {%{"id" => "a"}, 8}] =
               Catalog.ranking(data, %{"speed" => 1, "cost" => 3})
    end

    test "ties keep the agent's order", %{data: data} do
      assert [{%{"id" => "a"}, 0}, {%{"id" => "b"}, 0}] =
               Catalog.ranking(data, %{"speed" => 0, "cost" => 0})
    end

    test "the human's weights are kept in the agent's view and can be reset", %{data: data} do
      widget = %{kind: "comparison", data: data, human: %{}}

      {:ok, human, []} =
        Catalog.human_action(widget, "weight", %{"criterion" => "cost", "value" => "3"})

      assert Catalog.body_text(%{widget | human: human}) =~ "human weight 3"
      assert {:ok, %{}, []} = Catalog.human_action(%{widget | human: human}, "reset_weights", %{})

      assert {:error, _} =
               Catalog.human_action(widget, "weight", %{"criterion" => "cost", "value" => "9"})
    end
  end

  describe "quiz" do
    setup do
      {:ok, data} = Catalog.validate("quiz", Catalog.example("quiz"))
      %{data: data}
    end

    test "scores a choice answer and keeps the latest", %{data: data} do
      widget = %{kind: "quiz", data: data, human: %{}}

      {:ok, human, []} =
        Catalog.human_action(widget, "answer", %{"question" => "q1", "answer" => "a"})

      refute Catalog.quiz_passed?(data, human)

      {:ok, human, []} =
        Catalog.human_action(%{widget | human: human}, "answer", %{
          "question" => "q1",
          "answer" => "b"
        })

      assert human["answers"]["q1"]["correct"]
      assert Catalog.quiz_open_questions(data, human) == ["q2"]
    end

    test "only feedback and gate modes tell the agent, and self-study hides answers from its view",
         %{data: data} do
      self = %{kind: "quiz", data: data, human: %{}}

      assert {:ok, human, []} =
               Catalog.human_action(self, "answer", %{"question" => "q1", "answer" => "a"})

      refute Catalog.body_text(%{self | human: human}) =~ "Human's answer"

      feedback = %{self | data: Map.put(data, "mode", "feedback")}

      assert {:ok, human, [{"question:q1", message}]} =
               Catalog.human_action(feedback, "answer", %{"question" => "q1", "answer" => "a"})

      assert message =~ "incorrect"
      assert Catalog.body_text(%{feedback | human: human}) =~ "Human's answer: a — incorrect"
    end

    test "free text waits for the agent's judgement", %{data: data} do
      widget = %{kind: "quiz", data: Map.put(data, "mode", "feedback"), human: %{}}

      {:ok, human, [{"question:q2", message}]} =
        Catalog.human_action(widget, "answer", %{"question" => "q2", "answer" => "because"})

      assert message =~ "jarvis_widgets"
      assert human["answers"]["q2"]["correct"] == nil
      {:ok, judged} = Catalog.judge(%{widget | human: human}, "q2", true, "yes")
      assert judged["answers"]["q2"]["correct"]
    end

    test "changing a question clears its answer", %{data: data} do
      human = %{
        "answers" => %{
          "q1" => %{"answer" => ["b"], "correct" => true},
          "q2" => %{"answer" => "x", "correct" => true}
        }
      }

      changed = update_in(data, ["questions", Access.at(0), "prompt"], &(&1 <> " (reworded)"))
      assert %{"answers" => answers} = Catalog.reconcile("quiz", data, changed, human)
      assert Map.keys(answers) == ["q2"]
    end
  end

  test "findings keep the human's marks only for findings that remain" do
    data = %{"findings" => [%{"id" => "f1"}, %{"id" => "f2"}]}

    assert %{"marks" => %{"f1" => "agree"}} =
             Catalog.reconcile("findings", nil, %{"findings" => [%{"id" => "f1"}]}, %{
               "marks" => %{"f1" => "agree", "f2" => "fixed"}
             })

    widget = %{kind: "findings", data: data, human: %{}}

    assert {:ok, %{"marks" => %{"f2" => "fixed"}}, []} =
             Catalog.human_action(widget, "mark", %{"finding" => "f2", "mark" => "fixed"})

    assert {:error, _} =
             Catalog.human_action(widget, "mark", %{"finding" => "nope", "mark" => "fixed"})
  end

  test "a diagram render error is reported once per distinct source" do
    widget = %{kind: "diagram", data: %{"source" => "flowchart LR; A-->"}, human: %{}}

    assert {:ok, human, [{nil, message}]} =
             Catalog.human_action(widget, "render_error", %{"message" => "Parse error"})

    assert message =~ "Parse error"

    assert {:ok, _, []} =
             Catalog.human_action(%{widget | human: human}, "render_error", %{
               "message" => "Parse error"
             })

    assert {:ok, human, [_]} =
             Catalog.human_action(
               %{widget | human: human, data: %{"source" => "flowchart LR; B-->"}},
               "render_error",
               %{"message" => "again"}
             )

    assert human["error"] == "again"
  end

  describe "PR review widgets" do
    defp widget(kind, data, human \\ %{}) do
      {:ok, data} = Catalog.validate(kind, data)
      %{id: 1, kind: kind, data: data, human: human}
    end

    test "a discussion that was not read says so and cannot be empty" do
      assert {:error, _} = Catalog.validate("discussion", %{"status" => "not_read"})

      w = widget("discussion", %{"status" => "not_read", "error" => "gh: not signed in"})
      assert Catalog.text(w) =~ "NOT READ: gh: not signed in"

      assert Catalog.text(widget("discussion", %{"status" => "read"})) =~ "No existing discussion"
    end

    test "a discussion lists open items before resolved ones" do
      text = Catalog.text(widget("discussion", Catalog.example("discussion")))
      assert text =~ ~r/Unresolved.*i1.*i2.*Other.*i3/s
    end

    test "a round with the same head has no statuses" do
      data = Map.merge(Catalog.example("round"), %{"previous_head" => "b7c9e21"})
      assert {:error, [error]} = Catalog.validate("round", data)
      assert error =~ "no new commits"

      same = %{"number" => 2, "head" => "a", "previous_head" => "a"}
      assert Catalog.text(widget("round", same)) =~ "No new commits"
    end

    test "location_gone needs the old location, and humans only set resolved or open" do
      bad = %{
        "number" => 2,
        "head" => "b",
        "previous_head" => "a",
        "statuses" => [%{"finding" => "f1", "status" => "location_gone", "reason" => "x"}]
      }

      assert {:error, [error]} = Catalog.validate("round", bad)
      assert error =~ "old_location"

      w = widget("round", Catalog.example("round"))

      assert {:ok, %{"statuses" => %{"s3" => "open"}}, []} =
               Catalog.human_action(w, "status", %{"id" => "s3", "value" => "open"})

      assert {:error, _} = Catalog.human_action(w, "status", %{"id" => "s3", "value" => "agree"})

      assert {:error, _} =
               Catalog.human_action(w, "mark", %{"finding" => "f1", "mark" => "agree"})
    end

    test "a draft whose line is not in its hunk cannot be approved" do
      w = widget("draft_comments", Catalog.example("draft_comments"))
      assert Catalog.anchored?(Enum.at(w.data["comments"], 0))
      refute Catalog.anchored?(Enum.at(w.data["comments"], 1))
      assert {:ok, _, []} = Catalog.human_action(w, "approve", %{"comment" => "c1"})
      assert {:error, _} = Catalog.human_action(w, "approve", %{"comment" => "c2"})
    end

    test "posting needs an approved draft and a verdict" do
      w = widget("draft_comments", Catalog.example("draft_comments"))
      assert {:error, _} = Catalog.human_action(w, "post", %{})

      {:ok, h, []} = Catalog.human_action(w, "approve", %{"comment" => "c1"})

      assert {:error, "choose a verdict first"} =
               Catalog.human_action(%{w | human: h}, "post", %{})

      {:ok, h, []} = Catalog.human_action(%{w | human: h}, "verdict", %{"value" => "comment"})
      assert {:ok, _, [{"verdict", message}]} = Catalog.human_action(%{w | human: h}, "post", %{})
      assert message =~ "verdict comment"
      assert message =~ "c1"

      assert {:error, _} = Catalog.human_action(w, "verdict", %{"value" => "lgtm"})
    end

    test "an edited draft loses its approval and a moved head marks drafts out of date" do
      w = widget("draft_comments", Catalog.example("draft_comments"))
      {:ok, h, []} = Catalog.human_action(w, "approve", %{"comment" => "c1"})

      same = Catalog.reconcile("draft_comments", w.data, w.data, h)
      assert same["decisions"] == %{"c1" => "approved"}

      edited = update_in(w.data, ["comments", Access.at(0), "body"], fn _ -> "new text" end)
      assert Catalog.reconcile("draft_comments", w.data, edited, h)["decisions"] == %{}

      refute Catalog.stale?(w.data)
      assert Catalog.stale?(Map.put(w.data, "current_head", "ffff"))
    end

    test "posted drafts are not offered again" do
      w = widget("draft_comments", Catalog.example("draft_comments"))
      {:ok, h, []} = Catalog.human_action(w, "approve", %{"comment" => "c1"})
      data = put_in(w.data, ["comments", Access.at(0), "posted_url"], "https://example.test/1")
      assert Catalog.approved_drafts(data, h) == []
      assert Catalog.text(%{w | data: data, human: h}) =~ "posted https://example.test/1"
    end
  end
end
