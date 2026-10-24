defmodule Jarvis.Planning.Catalog do
  @moduledoc """
  The widget catalog: every widget kind Jarvis draws, its fields, its parts,
  and an example.

  Agents write widget data as JSON objects; `validate/2` checks them against
  the kind's fields and fills in part ids the agent left out. Parts are the
  elements of a widget a comment can point at, named `"<prefix>:<id>"` (for
  example `row:r2`, `node:api`, `option:q1/b`). `text/1` renders a widget for an
  agent, `human_action/4` applies what the human did with it.
  """

  @type errors :: [String.t()]

  @patterns ~w(ubiquitous event state unwanted optional)
  @tones ~w(info warning risk)
  @node_kinds ~w(person service component datastore queue external)
  @severities ~w(blocker major minor nit)
  @marks ~w(agree disagree fixed)
  @quiz_modes ~w(self_study feedback gate)
  @item_types ~w(conversation thread review)
  @review_states ~w(approved changes_requested commented)
  @finding_statuses ~w(resolved open location_gone)
  @verdicts ~w(approve request_changes comment)

  @kinds [
    {"prose", "Prose", "Markdown text, for what no other widget kind expresses better.",
     [{"text", :text, required: true}]},
    {"callout", "Callout", "A highlighted note: info, a warning, or a risk.",
     [
       {"tone", {:enum, @tones}, required: true},
       {"title", :string, required: true},
       {"body", :text, []}
     ]},
    {"requirement", "Requirement card",
     "One requirement in EARS form, shown as trigger → system → response. The human confirms or questions it. trigger is the part after When (event), While (state), If (unwanted), or Where (optional); leave it out for ubiquitous.",
     [
       {"id", :string, required: true, doc: "Requirement id, e.g. R1"},
       {"pattern", {:enum, @patterns}, required: true},
       {"trigger", :string, []},
       {"system", :string, required: true, doc: "The actor or system, e.g. the board"},
       {"response", :string, required: true, doc: "What it shall do, without 'shall'"}
     ]},
    {"examples", "Examples table",
     "Concrete examples of a rule: condition columns and an expected result. The human picks condition values to find the matching row.",
     [
       {"title", :string, []},
       {"columns", {:strings, 1}, required: true, doc: "Condition column names"},
       {"expected_label", :string, doc: "Heading of the result column (default Expected)"},
       {"rows",
        {:list, "row",
         [{"values", {:strings, 1}, required: true}, {"expected", :string, required: true}]},
        required: true, doc: "values: one per condition column, in order"}
     ]},
    {"glossary_term", "Glossary term", "A domain term, its meaning, and its limits.",
     [
       {"term", :string, required: true},
       {"meaning", :text, required: true},
       {"limits", :text, []}
     ]},
    {"decision", "Decision", "A decision, why it was taken, and what was rejected.",
     [
       {"decision", :string, required: true},
       {"reason", :text, required: true},
       {"alternatives", {:strings, 0}, doc: "Alternatives rejected"}
     ]},
    {"diagram", "Diagram",
     "A Mermaid diagram: flowchart, sequenceDiagram, stateDiagram-v2, classDiagram, erDiagram, or C4Context. Nodes, edges, participants, and messages become parts the human can click.",
     [
       {"title", :string, []},
       {"source", :text, required: true, doc: "Mermaid source"}
     ]},
    {"architecture", "Architecture graph",
     "Typed nodes in groups with labelled edges, laid out automatically, with an optional guided tour.",
     [
       {"title", :string, []},
       {"groups", {:list, "group", [{"label", :string, required: true}], ids: :required}, []},
       {"nodes",
        {:list, "node",
         [
           {"label", :string, required: true},
           {"kind", {:enum, @node_kinds}, required: true},
           {"group", :string, doc: "Group id"},
           {"description", :text, []}
         ], ids: :required}, required: true},
       {"edges",
        {:list, "edge",
         [
           {"from", :string, required: true},
           {"to", :string, required: true},
           {"label", :string, []}
         ]}, []},
       {"tour",
        {:list, "step",
         [
           {"title", :string, required: true},
           {"narration", :text, required: true},
           {"nodes", {:strings, 0}, doc: "Node ids to highlight"},
           {"edges", {:strings, 0}, doc: "Edge ids to highlight"}
         ]}, []}
     ]},
    {"quiz", "Quiz",
     "Questions that check understanding. mode self_study keeps answers in the browser, feedback sends them to the agent, gate makes the transition named in gates wait until every question is answered correctly.",
     [
       {"mode", {:enum, @quiz_modes}, required: true},
       {"gates", :string, doc: "Transition name the quiz gates; required in gate mode"},
       {"questions",
        {:list, "q",
         [
           {"prompt", :text, required: true},
           {"type", {:enum, ~w(single multiple text)}, required: true},
           {"options",
            {:list, "o",
             [
               {"text", :string, required: true},
               {"correct", :bool, []},
               {"explanation", :text, required: true}
             ]}, []},
           {"model_answer", :text, doc: "Required for text questions"}
         ]}, required: true}
     ]},
    {"comparison", "Comparison matrix",
     "Options scored 0-5 against weighted criteria (weight 0-5), ranked by score times weight. The human can re-weigh the criteria.",
     [
       {"criteria",
        {:list, "criterion",
         [{"label", :string, required: true}, {"weight", {:int, 0, 5}, required: true}],
         ids: :required}, required: true},
       {"options",
        {:list, "option",
         [
           {"label", :string, required: true},
           {"scores", {:map, {:int, 0, 5}}, required: true, doc: "criterion id => 0-5"},
           {"notes", {:map, :string}, doc: "criterion id => note"}
         ], ids: :required}, required: true},
       {"recommended", :string, doc: "Option id the agent recommends"}
     ]},
    {"sources", "Sources", "Sources with quoted passages, and the claims each source supports.",
     [
       {"sources",
        {:list, "source",
         [
           {"title", :string, required: true},
           {"url", :string, []},
           {"quote", :text, []}
         ], ids: :required}, required: true},
       {"claims",
        {:list, "claim",
         [{"text", :string, required: true}, {"sources", {:strings, 0}, required: true}]}, []}
     ]},
    {"walkthrough", "Code walkthrough",
     "Code explained one step at a time: file, lines, excerpt, narration.",
     [
       {"title", :string, []},
       {"steps",
        {:list, "step",
         [
           {"path", :string, required: true},
           {"lines", :string, doc: "e.g. 10-24"},
           {"language", :string, doc: "e.g. elixir"},
           {"code", :text, required: true},
           {"narration", :text, required: true}
         ]}, required: true}
     ]},
    {"findings", "Review findings",
     "Review findings with severity and location; the human marks each agree, disagree, or fixed.",
     [
       {"findings",
        {:list, "finding",
         [
           {"severity", {:enum, @severities}, required: true},
           {"path", :string, required: true},
           {"line", :string, []},
           {"explanation", :text, required: true},
           {"suggestion", :text, []}
         ]}, required: true}
     ]},
    {"discussion", "Existing PR discussion",
     "What others already said on a pull request: conversation comments, inline threads, and review verdicts. status not_read (with the error) means it could not be read, which is not the same as no discussion. Unresolved threads and requested changes are shown apart from the rest.",
     [
       {"status", {:enum, ~w(read not_read)}, required: true},
       {"error", :text, doc: "What failed; required when status is not_read"},
       {"items",
        {:list, "item",
         [
           {"type", {:enum, @item_types}, required: true},
           {"author", :string, required: true},
           {"body", :text, []},
           {"path", :string, doc: "Inline threads: file"},
           {"line", :string, doc: "Inline threads: line"},
           {"resolved", :bool, doc: "Inline threads: resolved on the code host"},
           {"state", {:enum, @review_states}, doc: "Reviews: the verdict"},
           {"url", :string, []}
         ]}, []}
     ]},
    {"round", "Review round",
     "One re-review round: the head commit reviewed, what changed since the previous round, and a proposed status for each earlier finding. The human confirms or changes each status. When head equals previous_head, there are no new commits: leave commits and statuses empty.",
     [
       {"number", {:int, 2, 99}, required: true},
       {"head", :string, required: true, doc: "Pull request head commit reviewed"},
       {"previous_head", :string, required: true, doc: "Head commit of the previous round"},
       {"commits",
        {:list, "commit", [{"sha", :string, required: true}, {"subject", :string, []}]}, []},
       {"statuses",
        {:list, "status",
         [
           {"finding", :string, required: true, doc: "Id of the earlier finding"},
           {"status", {:enum, @finding_statuses}, required: true},
           {"reason", :text, required: true},
           {"location", :string, doc: "path:line in the new code"},
           {"old_location", :string, doc: "Required when status is location_gone"}
         ]}, []}
     ]},
    {"draft_comments", "Draft review comments",
     "Review comments proposed for the code host, each on the diff hunk it attaches to. The human approves or drops each and chooses the verdict; nothing is posted before that. hunk is a unified diff hunk starting with its @@ header; line is a line number on side RIGHT (new file, default) or LEFT (old file) that must appear in the hunk. After posting, set posted_url on each posted comment.",
     [
       {"head", :string,
        required: true, doc: "Pull request head commit the drafts were made against"},
       {"current_head", :string, doc: "Set when the head has since moved"},
       {"comments",
        {:list, "c",
         [
           {"path", :string, required: true},
           {"line", :string, required: true},
           {"side", {:enum, ~w(RIGHT LEFT)}, []},
           {"hunk", :text, required: true},
           {"body", :text, required: true, doc: "The comment text exactly as it will be posted"},
           {"posted_url", :string, []}
         ]}, required: true}
     ]}
  ]

  @kind_names Enum.map(@kinds, &elem(&1, 0))

  def kinds, do: @kind_names
  def patterns, do: @patterns
  def node_kinds, do: @node_kinds
  def severities, do: @severities
  def marks, do: @marks
  def verdicts, do: @verdicts
  def finding_statuses, do: @finding_statuses

  def kind?(kind), do: kind in @kind_names

  def label(kind), do: kind |> fetch!() |> elem(1)
  def description(kind), do: kind |> fetch!() |> elem(2)
  def fields(kind), do: kind |> fetch!() |> elem(3)

  defp fetch!(kind), do: List.keyfind!(@kinds, kind, 0)

  ## Validation

  @doc """
  Checks widget data against its kind and returns it normalized: unknown
  fields rejected, part ids filled in where the agent left them out.
  """
  @spec validate(String.t(), term()) :: {:ok, map()} | {:error, errors()}
  def validate(kind, data) when is_map(data) do
    {normalized, errors} = check_object(fields(kind), stringify(data), "")

    errors = if errors == [], do: check(kind, normalized), else: errors

    case errors do
      [] -> {:ok, normalized}
      errors -> {:error, errors}
    end
  end

  def validate(_kind, _data), do: {:error, ["data: must be an object"]}

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  defp check_object(fields, data, path, id_rule \\ nil, default_id \\ nil) do
    names = Enum.map(fields, &elem(&1, 0))
    allowed = if id_rule, do: ["id" | names], else: names

    unknown =
      for key <- Map.keys(data), key not in allowed do
        "#{path}#{key}: unknown field (allowed: #{Enum.join(allowed, ", ")})"
      end

    {data, id_errors} =
      case {id_rule, Map.get(data, "id")} do
        {nil, _} -> {data, []}
        {_, id} when is_binary(id) and id != "" -> {data, []}
        {:required, _} -> {data, ["#{path}id: required"]}
        {:optional, nil} -> {Map.put(data, "id", default_id), []}
        {:optional, _} -> {data, ["#{path}id: must be a non-empty string"]}
      end

    Enum.reduce(fields, {data, unknown ++ id_errors}, fn {name, type, opts}, {acc, errors} ->
      field_path = "#{path}#{name}"

      case Map.fetch(acc, name) do
        {:ok, value} when value not in [nil, ""] ->
          case check_value(type, value, field_path) do
            {:ok, value} -> {Map.put(acc, name, value), errors}
            {:error, more} -> {acc, errors ++ more}
          end

        _ ->
          acc = Map.delete(acc, name)

          if opts[:required],
            do: {acc, errors ++ ["#{field_path}: required"]},
            else: {acc, errors}
      end
    end)
  end

  defp check_value(:string, v, _p) when is_binary(v) and byte_size(v) <= 2_000,
    do: {:ok, String.trim(v)}

  defp check_value(:string, _v, p), do: {:error, ["#{p}: must be a string of at most 2000 bytes"]}

  defp check_value(:text, v, _p) when is_binary(v) and byte_size(v) <= 50_000, do: {:ok, v}
  defp check_value(:text, _v, p), do: {:error, ["#{p}: must be text of at most 50000 bytes"]}

  defp check_value(:bool, v, _p) when is_boolean(v), do: {:ok, v}
  defp check_value(:bool, _v, p), do: {:error, ["#{p}: must be true or false"]}

  defp check_value({:enum, values}, v, p) do
    if v in values,
      do: {:ok, v},
      else: {:error, ["#{p}: must be one of #{Enum.join(values, ", ")}"]}
  end

  defp check_value({:int, min, max}, v, _p) when is_integer(v) and v >= min and v <= max,
    do: {:ok, v}

  defp check_value({:int, min, max}, _v, p),
    do: {:error, ["#{p}: must be a whole number from #{min} to #{max}"]}

  defp check_value({:strings, min}, v, p) when is_list(v) do
    cond do
      not Enum.all?(v, &is_binary/1) -> {:error, ["#{p}: must be a list of strings"]}
      length(v) < min -> {:error, ["#{p}: needs at least #{min} item(s)"]}
      true -> {:ok, Enum.map(v, &String.trim/1)}
    end
  end

  defp check_value({:strings, _}, _v, p), do: {:error, ["#{p}: must be a list of strings"]}

  defp check_value({:map, type}, v, p) when is_map(v) do
    Enum.reduce(v, {:ok, %{}}, fn {k, value}, acc ->
      case {acc, check_value(type, value, "#{p}.#{k}")} do
        {{:ok, map}, {:ok, value}} -> {:ok, Map.put(map, k, value)}
        {{:ok, _}, {:error, e}} -> {:error, e}
        {{:error, e1}, {:error, e2}} -> {:error, e1 ++ e2}
        {{:error, e}, _} -> {:error, e}
      end
    end)
  end

  defp check_value({:map, _}, _v, p), do: {:error, ["#{p}: must be an object"]}

  defp check_value({:list, prefix, fields}, v, p),
    do: check_value({:list, prefix, fields, []}, v, p)

  defp check_value({:list, prefix, fields, opts}, v, p) when is_list(v) do
    id_rule = Keyword.get(opts, :ids, :optional)

    {items, errors} =
      v
      |> Enum.with_index(1)
      |> Enum.map_reduce([], fn
        {item, i}, errors when is_map(item) ->
          {item, more} = check_object(fields, item, "#{p}[#{i}].", id_rule, "#{prefix}#{i}")
          {item, errors ++ more}

        {_item, i}, errors ->
          {nil, errors ++ ["#{p}[#{i}]: must be an object"]}
      end)

    ids = items |> Enum.reject(&is_nil/1) |> Enum.map(& &1["id"])
    dupes = ids -- Enum.uniq(ids)
    dupe_errors = for id <- Enum.uniq(dupes), do: "#{p}: id #{inspect(id)} is used twice"

    case errors ++ dupe_errors do
      [] -> {:ok, items}
      errors -> {:error, errors}
    end
  end

  defp check_value({:list, _, _, _}, _v, p), do: {:error, ["#{p}: must be a list"]}

  # Rules that span fields.
  defp check("requirement", %{"pattern" => pattern} = d) do
    if pattern != "ubiquitous" and blank?(d["trigger"]),
      do: ["trigger: required for the #{pattern} pattern"],
      else: []
  end

  defp check("examples", %{"columns" => columns, "rows" => rows}) do
    for {row, i} <- Enum.with_index(rows, 1), length(row["values"]) != length(columns) do
      "rows[#{i}].values: needs #{length(columns)} value(s), one per column"
    end
  end

  defp check("architecture", d) do
    nodes = ids(d["nodes"])
    groups = ids(d["groups"])
    edges = ids(d["edges"])

    group_errors =
      for n <- d["nodes"], n["group"] && n["group"] not in groups do
        "nodes[#{n["id"]}].group: no group #{inspect(n["group"])}"
      end

    edge_errors =
      for e <- d["edges"] || [], end_ <- ["from", "to"], e[end_] not in nodes do
        "edges[#{e["id"]}].#{end_}: no node #{inspect(e[end_])}"
      end

    tour_errors =
      for s <- d["tour"] || [],
          {field, known} <- [{"nodes", nodes}, {"edges", edges}],
          ref <- s[field] || [],
          ref not in known do
        "tour[#{s["id"]}].#{field}: no #{String.trim_trailing(field, "s")} #{inspect(ref)}"
      end

    group_errors ++ edge_errors ++ tour_errors
  end

  defp check("quiz", d) do
    gate =
      if d["mode"] == "gate" and blank?(d["gates"]),
        do: ["gates: required in gate mode"],
        else: []

    questions =
      Enum.flat_map(d["questions"], fn q ->
        options = q["options"] || []
        correct = Enum.count(options, & &1["correct"])
        p = "questions[#{q["id"]}]"

        case q["type"] do
          "text" ->
            if blank?(q["model_answer"]), do: ["#{p}.model_answer: required for text"], else: []

          "single" ->
            List.flatten([
              if(length(options) < 2, do: ["#{p}.options: needs at least 2"], else: []),
              if(correct != 1, do: ["#{p}.options: exactly one must be correct"], else: [])
            ])

          "multiple" ->
            List.flatten([
              if(length(options) < 2, do: ["#{p}.options: needs at least 2"], else: []),
              if(correct < 1, do: ["#{p}.options: at least one must be correct"], else: [])
            ])
        end
      end)

    gate ++ questions
  end

  defp check("comparison", d) do
    criteria = ids(d["criteria"])
    options = ids(d["options"])

    score_errors =
      for o <- d["options"], key <- Map.keys(o["scores"]), key not in criteria do
        "options[#{o["id"]}].scores: no criterion #{inspect(key)}"
      end

    recommended =
      if d["recommended"] && d["recommended"] not in options,
        do: ["recommended: no option #{inspect(d["recommended"])}"],
        else: []

    score_errors ++ recommended
  end

  defp check("sources", d) do
    sources = ids(d["sources"])

    for c <- d["claims"] || [], ref <- c["sources"], ref not in sources do
      "claims[#{c["id"]}].sources: no source #{inspect(ref)}"
    end
  end

  defp check("discussion", d) do
    cond do
      d["status"] == "not_read" and blank?(d["error"]) ->
        ["error: required when not_read"]

      d["status"] == "not_read" and (d["items"] || []) != [] ->
        ["items: must be empty when not_read"]

      true ->
        []
    end
  end

  defp check("round", d) do
    same? = d["head"] == d["previous_head"]
    statuses = d["statuses"] || []

    same_errors =
      if same? and (statuses != [] or (d["commits"] || []) != []),
        do: ["statuses, commits: must be empty when head equals previous_head (no new commits)"],
        else: []

    gone_errors =
      for s <- statuses, s["status"] == "location_gone", blank?(s["old_location"]) do
        "statuses[#{s["id"]}].old_location: required when location_gone"
      end

    same_errors ++ gone_errors
  end

  defp check("draft_comments", d) do
    Enum.flat_map(d["comments"], fn c ->
      p = "comments[#{c["id"]}]"

      cond do
        not String.match?(c["line"], ~r/^\d+$/) -> ["#{p}.line: must be a line number"]
        hunk_lines(c["hunk"]) == [] -> ["#{p}.hunk: must start with a @@ -a,b +c,d @@ header"]
        true -> []
      end
    end)
  end

  defp check(_kind, _data), do: []

  defp ids(nil), do: []
  defp ids(items), do: Enum.map(items, & &1["id"])

  defp blank?(value), do: value in [nil, ""]

  ## Parts

  @doc """
  The parts of a widget as `{part_id, label, text}`. A diagram's parts are
  found in the browser, so any part id is accepted for it (see `part/2`).
  """
  def parts(%{kind: kind, data: data}), do: parts(kind, data)

  def parts("examples", d) do
    for {row, i} <- Enum.with_index(d["rows"], 1) do
      {"row:#{row["id"]}", "Row #{i}", example_row_text(d, row)}
    end
  end

  def parts("architecture", d) do
    Enum.map(d["groups"] || [], &{"group:#{&1["id"]}", "Group #{&1["label"]}", &1["label"]}) ++
      Enum.map(d["nodes"], fn n ->
        {"node:#{n["id"]}", "Node #{n["label"]}",
         "#{n["label"]} (#{n["kind"]}) #{n["description"]}" |> String.trim()}
      end) ++
      Enum.map(d["edges"] || [], fn e ->
        {"edge:#{e["id"]}", "Edge #{e["from"]} → #{e["to"]}",
         "#{e["from"]} → #{e["to"]} #{e["label"]}" |> String.trim()}
      end) ++
      Enum.map(
        d["tour"] || [],
        &{"step:#{&1["id"]}", "Tour step #{&1["title"]}", &1["narration"]}
      )
  end

  def parts("quiz", d) do
    Enum.flat_map(d["questions"], fn q ->
      [
        {"question:#{q["id"]}", "Question #{q["id"]}", q["prompt"]}
        | Enum.map(q["options"] || [], fn o ->
            {"option:#{q["id"]}/#{o["id"]}", "Option #{o["id"]} of #{q["id"]}", o["text"]}
          end)
      ]
    end)
  end

  def parts("comparison", d) do
    Enum.map(d["options"], &{"option:#{&1["id"]}", "Option #{&1["label"]}", &1["label"]}) ++
      Enum.map(d["criteria"], &{"criterion:#{&1["id"]}", "Criterion #{&1["label"]}", &1["label"]})
  end

  def parts("sources", d) do
    Enum.map(d["sources"], fn s ->
      {"source:#{s["id"]}", "Source #{s["title"]}", "#{s["title"]} #{s["url"]}" |> String.trim()}
    end) ++
      Enum.map(d["claims"] || [], &{"claim:#{&1["id"]}", "Claim #{&1["id"]}", &1["text"]})
  end

  def parts("walkthrough", d) do
    for {s, i} <- Enum.with_index(d["steps"], 1) do
      {"step:#{s["id"]}", "Step #{i} (#{s["path"]})", s["narration"]}
    end
  end

  def parts("findings", d) do
    for f <- d["findings"] do
      {"finding:#{f["id"]}", "Finding #{f["id"]} (#{f["severity"]})",
       "#{f["path"]}#{if f["line"], do: ":#{f["line"]}"} #{f["explanation"]}"}
    end
  end

  def parts("discussion", d) do
    for i <- d["items"] || [] do
      {"item:#{i["id"]}", "#{i["type"]} by #{i["author"]}", item_text(i)}
    end
  end

  def parts("round", d) do
    Enum.map(
      d["commits"] || [],
      &{"commit:#{&1["id"]}", "Commit #{&1["sha"]}", &1["subject"] || &1["sha"]}
    ) ++
      Enum.map(d["statuses"] || [], fn s ->
        {"status:#{s["id"]}", "Status of finding #{s["finding"]}",
         "#{s["finding"]} #{s["status"]}: #{s["reason"]}"}
      end)
  end

  def parts("draft_comments", d) do
    Enum.flat_map(d["comments"], fn c ->
      [
        {"comment:#{c["id"]}", "Draft comment #{c["id"]}", c["body"]},
        {"anchor:#{c["id"]}", "Anchor of #{c["id"]}", "#{c["path"]}:#{c["line"]}"}
      ]
    end) ++ [{"verdict", "Verdict", "The verdict of the review"}]
  end

  def parts(_kind, _data), do: []

  @doc "The part's `{label, text}`, or `nil` when the widget has no such part."
  def part(%{kind: "diagram"}, part) when is_binary(part), do: {part, part}

  def part(widget, part) do
    case List.keyfind(parts(widget), part, 0) do
      {_, label, text} -> {label, text}
      nil -> nil
    end
  end

  ## Text for agents

  @doc "The widget as text for an agent, with its widget id, kind, and part ids."
  def text(%{id: id, kind: kind} = widget) do
    "#### W#{id} · #{kind}\n\n" <> body_text(widget)
  end

  @doc "The widget's content as plain text, without its header."
  def body_text(%{kind: "prose", data: d}), do: d["text"]

  def body_text(%{kind: "callout", data: d}),
    do:
      "**#{String.upcase(d["tone"])}: #{d["title"]}**" <>
        if(d["body"], do: "\n\n" <> d["body"], else: "")

  def body_text(%{kind: "requirement", data: d, human: h}) do
    state = if h["confirmed"], do: "confirmed", else: "not confirmed"
    "**#{d["id"]}** (#{d["pattern"]}, #{state}) #{requirement_sentence(d)}"
  end

  def body_text(%{kind: "examples", data: d}) do
    head =
      "| " <> Enum.join(d["columns"] ++ [d["expected_label"] || "Expected"], " | ") <> " | part |"

    sep = "|" <> String.duplicate(" --- |", length(d["columns"]) + 2)

    rows =
      for row <- d["rows"] do
        "| " <> Enum.join(row["values"] ++ [row["expected"]], " | ") <> " | row:#{row["id"]} |"
      end

    Enum.join(
      [d["title"] && "**#{d["title"]}**", head, sep | rows] |> Enum.reject(&is_nil/1),
      "\n"
    )
  end

  def body_text(%{kind: "glossary_term", data: d}),
    do:
      "**#{d["term"]}:** #{d["meaning"]}" <>
        if(d["limits"], do: " Limits: #{d["limits"]}", else: "")

  def body_text(%{kind: "decision", data: d}) do
    alts = d["alternatives"] || []

    "**#{d["decision"]}** — #{d["reason"]}" <>
      if(alts == [], do: "", else: "\nRejected: " <> Enum.join(alts, "; "))
  end

  def body_text(%{kind: "diagram", data: d} = w) do
    error = if w.human["error"], do: "\nRender error: #{w.human["error"]}", else: ""
    "#{d["title"]}\n```mermaid\n#{d["source"]}\n```" <> error
  end

  def body_text(%{kind: "architecture", data: d}) do
    groups = Enum.map(d["groups"] || [], &"- group:#{&1["id"]} #{&1["label"]}")

    nodes =
      Enum.map(d["nodes"], fn n ->
        "- node:#{n["id"]} #{n["label"]} (#{n["kind"]}#{if n["group"], do: ", in #{n["group"]}"})" <>
          if(n["description"], do: ": #{n["description"]}", else: "")
      end)

    edges =
      Enum.map(
        d["edges"] || [],
        &"- edge:#{&1["id"]} #{&1["from"]} → #{&1["to"]}#{if &1["label"], do: " (#{&1["label"]})"}"
      )

    tour = Enum.map(d["tour"] || [], &"- step:#{&1["id"]} #{&1["title"]}: #{&1["narration"]}")

    ([d["title"] && "**#{d["title"]}**", "Groups:", groups, "Nodes:", nodes, "Edges:", edges] ++
       if(tour == [], do: [], else: ["Tour:", tour]))
    |> List.flatten()
    |> Enum.reject(&(is_nil(&1) or (&1 == "Groups:" and groups == [])))
    |> Enum.join("\n")
  end

  def body_text(%{kind: "quiz", data: d, human: h}) do
    answers = if d["mode"] == "self_study", do: %{}, else: h["answers"] || %{}

    header =
      "Mode: #{d["mode"]}" <>
        if(d["gates"], do: ", gates the transition \"#{d["gates"]}\"", else: "")

    questions =
      Enum.map(d["questions"], fn q ->
        options =
          Enum.map(q["options"] || [], fn o ->
            "  - option:#{q["id"]}/#{o["id"]} #{o["text"]}#{if o["correct"], do: " (correct)"}"
          end)

        answer =
          case answers[q["id"]] do
            nil -> []
            a -> ["  Human's answer: #{format_answer(a["answer"])} — #{verdict(a)}"]
          end

        ["- question:#{q["id"]} (#{q["type"]}) #{q["prompt"]}" | options ++ answer]
      end)

    Enum.join([header | List.flatten(questions)], "\n")
  end

  def body_text(%{kind: "comparison", data: d, human: h}) do
    agent = ranking(d, %{})
    human_weights = h["weights"] || %{}

    criteria =
      Enum.map(d["criteria"], fn c ->
        human =
          if Map.has_key?(human_weights, c["id"]),
            do: ", human weight #{human_weights[c["id"]]}",
            else: ""

        "- criterion:#{c["id"]} #{c["label"]} (agent weight #{c["weight"]}#{human})"
      end)

    options =
      Enum.map(agent, fn {o, total} ->
        scores = Enum.map_join(d["criteria"], ", ", &"#{&1["id"]} #{o["scores"][&1["id"]] || 0}")
        rec = if d["recommended"] == o["id"], do: " (recommended)", else: ""
        "- option:#{o["id"]} #{o["label"]}#{rec}: #{scores}; total #{total}"
      end)

    human_rank =
      if human_weights == %{},
        do: [],
        else: [
          "Ranking under the human's weights: " <>
            Enum.map_join(ranking(d, human_weights), ", ", &"#{elem(&1, 0)["id"]} #{elem(&1, 1)}")
        ]

    Enum.join(
      ["Criteria:" | criteria] ++
        ["Options, ranked by the agent's weights:" | options] ++ human_rank,
      "\n"
    )
  end

  def body_text(%{kind: "sources", data: d}) do
    sources =
      Enum.map(
        d["sources"],
        &("- source:#{&1["id"]} #{&1["title"]} #{&1["url"]}" <>
            if(&1["quote"], do: "\n  > #{&1["quote"]}", else: ""))
      )

    claims =
      Enum.map(
        d["claims"] || [],
        &"- claim:#{&1["id"]} #{&1["text"]} [#{Enum.join(&1["sources"], ", ")}]"
      )

    Enum.join(["Sources:" | sources] ++ ["Claims:" | claims], "\n")
  end

  def body_text(%{kind: "walkthrough", data: d}) do
    steps =
      for {s, i} <- Enum.with_index(d["steps"], 1) do
        "- step:#{s["id"]} (#{i}) #{s["path"]}#{if s["lines"], do: ":#{s["lines"]}"}: #{s["narration"]}"
      end

    Enum.join([d["title"] && "**#{d["title"]}**" | steps] |> Enum.reject(&is_nil/1), "\n")
  end

  def body_text(%{kind: "findings", data: d, human: h}) do
    marks = h["marks"] || %{}

    Enum.map_join(d["findings"], "\n", fn f ->
      mark = if marks[f["id"]], do: " — human: #{marks[f["id"]]}", else: ""

      "- finding:#{f["id"]} [#{f["severity"]}] #{f["path"]}#{if f["line"], do: ":#{f["line"]}"} #{f["explanation"]}#{mark}"
    end)
  end

  def body_text(%{kind: "discussion", data: d}) do
    items = d["items"] || []

    cond do
      d["status"] == "not_read" ->
        "Discussion NOT READ: #{d["error"]}"

      items == [] ->
        "No existing discussion."

      true ->
        {open, rest} = Enum.split_with(items, &open_item?/1)

        Enum.join(
          ["Unresolved and requested changes:"] ++
            Enum.map(open, &"- item:#{&1["id"]} #{item_text(&1)}") ++
            ["Other:"] ++ Enum.map(rest, &"- item:#{&1["id"]} #{item_text(&1)}"),
          "\n"
        )
    end
  end

  def body_text(%{kind: "round", data: d, human: h}) do
    head = "**Round #{d["number"]}** reviewed #{d["head"]} (previous #{d["previous_head"]})"

    if d["head"] == d["previous_head"] do
      head <> "\nNo new commits; finding statuses unchanged."
    else
      human = h["statuses"] || %{}

      commits =
        Enum.map(d["commits"] || [], &"- commit:#{&1["id"]} #{&1["sha"]} #{&1["subject"]}")

      statuses =
        Enum.map(d["statuses"] || [], fn s ->
          where =
            if s["status"] == "location_gone",
              do: " (location gone, was #{s["old_location"]})",
              else: if(s["location"], do: " (#{s["location"]})", else: "")

          mine =
            if human[s["id"]], do: " — human: #{human[s["id"]]}", else: " — human: not confirmed"

          "- status:#{s["id"]} finding #{s["finding"]}: #{s["status"]}#{where}. #{s["reason"]}#{mine}"
        end)

      Enum.join([head, "Commits:" | commits] ++ ["Proposed statuses:" | statuses], "\n")
    end
  end

  def body_text(%{kind: "draft_comments", data: d, human: h}) do
    decisions = h["decisions"] || %{}
    verdict = h["verdict"] || "none chosen"
    stale = if stale?(d), do: " POSSIBLY OUT OF DATE: head is now #{d["current_head"]}.", else: ""

    comments =
      Enum.map(d["comments"], fn c ->
        state =
          cond do
            c["posted_url"] -> "posted #{c["posted_url"]}"
            not anchored?(c) -> "NOT IN THE DIFF, cannot be approved until re-anchored"
            true -> decisions[c["id"]] || "undecided"
          end

        "- comment:#{c["id"]} #{c["path"]}:#{c["line"]} (#{c["side"] || "RIGHT"}) [#{state}] #{c["body"]}"
      end)

    Enum.join(
      ["Drafted against head #{d["head"]}.#{stale}", "Verdict (verdict): #{verdict}" | comments],
      "\n"
    )
  end

  defp open_item?(%{"type" => "thread"} = i), do: i["resolved"] != true
  defp open_item?(%{"type" => "review"} = i), do: i["state"] == "changes_requested"
  defp open_item?(_), do: false

  defp item_text(i) do
    where = if i["path"], do: " #{i["path"]}#{if i["line"], do: ":#{i["line"]}"}", else: ""
    state = Enum.find_value([i["state"], i["resolved"] == true && "resolved"], &(&1 || nil))
    "#{i["type"]} by #{i["author"]}#{where}#{if state, do: " [#{state}]"}: #{i["body"]}"
  end

  @doc "True for discussion items that are open: unresolved threads and requested changes."
  def open_item(i), do: open_item?(i)

  @doc "True when the pull request head moved since the drafts were made."
  def stale?(d), do: d["current_head"] not in [nil, d["head"]]

  @doc "True when the comment's line appears in its diff hunk, on its side."
  def anchored?(c) do
    key = if c["side"] == "LEFT", do: :old, else: :new
    line = String.to_integer(c["line"])
    Enum.any?(hunk_lines(c["hunk"]), &(&1[key] == line))
  end

  @doc """
  A unified diff hunk as `%{kind, old, new, text}` lines (`kind` is :add, :del,
  or :ctx; `old` and `new` are line numbers or nil). Empty without a valid @@ header.
  """
  def hunk_lines(hunk) do
    [header | body] = String.split(hunk, "\n")

    case Regex.run(~r/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/, header) do
      [_, old, new] ->
        {lines, _} =
          Enum.map_reduce(body, {String.to_integer(old), String.to_integer(new)}, fn
            "+" <> _ = t, {o, n} -> {%{kind: :add, old: nil, new: n, text: t}, {o, n + 1}}
            "-" <> _ = t, {o, n} -> {%{kind: :del, old: o, new: nil, text: t}, {o + 1, n}}
            t, {o, n} -> {%{kind: :ctx, old: o, new: n, text: t}, {o + 1, n + 1}}
          end)

        lines

      _ ->
        []
    end
  end

  defp format_answer(list) when is_list(list), do: Enum.join(list, ", ")
  defp format_answer(text), do: inspect(text)

  defp verdict(%{"correct" => true}), do: "correct"
  defp verdict(%{"correct" => false}), do: "incorrect"
  defp verdict(_), do: "awaiting your judgement"

  @doc "The requirement as one EARS sentence."
  def requirement_sentence(d) do
    lead =
      case d["pattern"] do
        "ubiquitous" -> "The #{d["system"]}"
        "event" -> "When #{d["trigger"]}, the #{d["system"]}"
        "state" -> "While #{d["trigger"]}, the #{d["system"]}"
        "unwanted" -> "If #{d["trigger"]}, then the #{d["system"]}"
        "optional" -> "Where #{d["trigger"]}, the #{d["system"]}"
      end

    "#{lead} shall #{d["response"]}."
  end

  @doc "The keyword that opens each EARS pattern."
  def pattern_keyword("ubiquitous"), do: nil
  def pattern_keyword("event"), do: "When"
  def pattern_keyword("state"), do: "While"
  def pattern_keyword("unwanted"), do: "If"
  def pattern_keyword("optional"), do: "Where"

  defp example_row_text(d, row) do
    conditions = Enum.zip_with(d["columns"], row["values"], &"#{&1} #{&2}") |> Enum.join(", ")
    "#{conditions} → #{row["expected"]}"
  end

  ## Comparison

  @doc """
  Options with their weighted totals, highest first; ties keep the agent's
  order. `weights` overrides the agent's weight per criterion id.
  """
  def ranking(d, weights) do
    d["options"]
    |> Enum.with_index()
    |> Enum.map(fn {o, i} ->
      total =
        Enum.reduce(d["criteria"], 0, fn c, sum ->
          weight = Map.get(weights, c["id"], c["weight"])
          sum + weight * Map.get(o["scores"], c["id"], 0)
        end)

      {o, total, i}
    end)
    |> Enum.sort_by(fn {_, total, i} -> {-total, i} end)
    |> Enum.map(fn {o, total, _} -> {o, total} end)
  end

  ## Quiz

  @doc "True when every question of the quiz has a correct latest answer."
  def quiz_passed?(%{"questions" => questions}, human) do
    answers = human["answers"] || %{}
    Enum.all?(questions, &(get_in(answers, [&1["id"], "correct"]) == true))
  end

  @doc "Ids of the quiz's questions without a correct latest answer."
  def quiz_open_questions(%{"questions" => questions}, human) do
    answers = human["answers"] || %{}
    for q <- questions, get_in(answers, [q["id"], "correct"]) != true, do: q["id"]
  end

  ## The human's side

  @doc """
  Applies what the human did with a widget and returns the new `human` map and
  what to tell the listening session, as `{part, message}` pairs.
  """
  def human_action(widget, action, params)

  def human_action(%{kind: "requirement", human: h}, "confirm", _),
    do: {:ok, Map.put(h, "confirmed", true), []}

  def human_action(%{kind: "requirement", human: h}, "unconfirm", _),
    do: {:ok, Map.delete(h, "confirmed"), []}

  def human_action(%{kind: "comparison", data: d, human: h}, "weight", %{
        "criterion" => c,
        "value" => v
      }) do
    with true <- c in ids(d["criteria"]),
         {weight, ""} when weight in 0..5 <- Integer.parse(to_string(v)) do
      {:ok, Map.update(h, "weights", %{c => weight}, &Map.put(&1, c, weight)), []}
    else
      _ -> {:error, "weight must be 0 to 5 for a known criterion"}
    end
  end

  def human_action(%{kind: "comparison", human: h}, "reset_weights", _),
    do: {:ok, Map.delete(h, "weights"), []}

  def human_action(%{kind: "findings", data: d, human: h}, "mark", %{"finding" => f, "mark" => m}) do
    if f in ids(d["findings"]) and m in @marks,
      do: {:ok, Map.update(h, "marks", %{f => m}, &Map.put(&1, f, m)), []},
      else: {:error, "unknown finding or mark"}
  end

  def human_action(%{kind: "diagram", data: d, human: h}, "render_error", %{"message" => msg}) do
    hash = :erlang.phash2(d["source"])

    if h["error_hash"] == hash do
      {:ok, h, []}
    else
      {:ok, Map.merge(h, %{"error" => msg, "error_hash" => hash}),
       [{nil, "The diagram failed to render: #{msg}. Fix its Mermaid source."}]}
    end
  end

  def human_action(%{kind: "diagram", human: h}, "rendered", _) do
    {:ok, Map.drop(h, ["error"]), []}
  end

  def human_action(%{kind: "quiz", data: d, human: h}, "answer", %{"question" => qid} = params) do
    case Enum.find(d["questions"], &(&1["id"] == qid)) do
      nil -> {:error, "no such question"}
      q -> answer(d, h, q, params["answer"])
    end
  end

  def human_action(%{kind: "round", data: d, human: h}, "status", %{"id" => id, "value" => v}) do
    if id in ids(d["statuses"] || []) and v in ["resolved", "open"],
      do: {:ok, Map.update(h, "statuses", %{id => v}, &Map.put(&1, id, v)), []},
      else: {:error, "unknown status or value"}
  end

  def human_action(%{kind: "draft_comments", data: d, human: h}, action, %{"comment" => id})
      when action in ["approve", "drop", "undecide"] do
    c = Enum.find(d["comments"], &(&1["id"] == id))

    cond do
      c == nil ->
        {:error, "no such draft comment"}

      c["posted_url"] ->
        {:error, "already posted"}

      action == "approve" and not anchored?(c) ->
        {:error, "its line is not in the diff"}

      action == "undecide" ->
        {:ok, Map.update(h, "decisions", %{}, &Map.delete(&1, id)), []}

      true ->
        {:ok, put_decision(h, id, if(action == "approve", do: "approved", else: "dropped")), []}
    end
  end

  def human_action(%{kind: "draft_comments", human: h}, "verdict", %{"value" => v})
      when v in @verdicts,
      do: {:ok, Map.put(h, "verdict", v), []}

  def human_action(%{kind: "draft_comments", data: d, human: h}, "post", _) do
    approved = approved_drafts(d, h)

    cond do
      approved == [] ->
        {:error, "approve at least one draft comment first"}

      h["verdict"] == nil ->
        {:error, "choose a verdict first"}

      true ->
        list = Enum.map_join(approved, ", ", & &1["id"])

        {:ok, h,
         [
           {"verdict",
            "Post the review now: verdict #{h["verdict"]}, draft comments #{list}, as one review through gh, and nothing else. Then set posted_url on each posted comment."}
         ]}
    end
  end

  def human_action(_widget, _action, _params),
    do: {:error, "this widget does not take that action"}

  defp put_decision(h, id, decision),
    do: Map.update(h, "decisions", %{id => decision}, &Map.put(&1, id, decision))

  @doc "Draft comments the human approved that are not posted yet."
  def approved_drafts(d, h) do
    decisions = h["decisions"] || %{}
    Enum.filter(d["comments"], &(decisions[&1["id"]] == "approved" and &1["posted_url"] == nil))
  end

  defp answer(d, h, %{"type" => "text"} = q, text) when is_binary(text) and text != "" do
    entry = %{"answer" => text, "correct" => nil}
    h = put_answer(h, q["id"], entry)

    notes =
      if d["mode"] == "self_study",
        do: [],
        else: [
          {"question:#{q["id"]}",
           "Quiz answer to #{q["id"]} (\"#{q["prompt"]}\"): #{text}\n\nJudge it with jarvis_widgets op judge (question #{q["id"]}, correct, explanation)."}
        ]

    {:ok, h, notes}
  end

  defp answer(d, h, %{"type" => type} = q, chosen) when type in ["single", "multiple"] do
    chosen = chosen |> List.wrap() |> Enum.map(&to_string/1) |> Enum.uniq()
    option_ids = ids(q["options"])

    cond do
      chosen == [] or Enum.any?(chosen, &(&1 not in option_ids)) ->
        {:error, "choose one of the question's options"}

      type == "single" and length(chosen) != 1 ->
        {:error, "choose exactly one option"}

      true ->
        correct_ids = for o <- q["options"], o["correct"], do: o["id"]
        correct = Enum.sort(chosen) == Enum.sort(correct_ids)
        h = put_answer(h, q["id"], %{"answer" => chosen, "correct" => correct})

        notes =
          if d["mode"] == "feedback",
            do: [
              {"question:#{q["id"]}",
               "Quiz answer to #{q["id"]} (\"#{q["prompt"]}\"): chose #{Enum.join(chosen, ", ")} — #{if correct, do: "correct", else: "incorrect"}. An incorrect answer may show an explanation to improve."}
            ],
            else: []

        {:ok, h, notes}
    end
  end

  defp answer(_d, _h, _q, _answer), do: {:error, "write an answer first"}

  defp put_answer(h, qid, entry),
    do: Map.update(h, "answers", %{qid => entry}, &Map.put(&1, qid, entry))

  @doc "An agent's verdict on the human's free-text answer."
  def judge(%{kind: "quiz", human: h}, qid, correct, explanation) when is_boolean(correct) do
    case get_in(h, ["answers", qid]) do
      nil ->
        {:error, "question #{qid} has no answer to judge"}

      entry ->
        {:ok,
         put_answer(h, qid, Map.merge(entry, %{"correct" => correct, "verdict" => explanation}))}
    end
  end

  def judge(_widget, _qid, _correct, _explanation),
    do: {:error, "judge needs a quiz widget, a question, and correct true or false"}

  @doc """
  Keeps the human's state in step with new agent data: a changed requirement
  is no longer confirmed, a changed question loses its answer, removed
  criteria and findings lose their weights and marks.
  """
  def reconcile("requirement", old, new, h) do
    keys = ~w(pattern trigger system response)
    if Map.take(old, keys) == Map.take(new, keys), do: h, else: Map.delete(h, "confirmed")
  end

  def reconcile("quiz", old, new, h) do
    old_q = Map.new(old["questions"], &{&1["id"], &1})
    new_q = Map.new(new["questions"], &{&1["id"], &1})

    answers =
      for {qid, a} <- h["answers"] || %{},
          Map.get(old_q, qid) == Map.get(new_q, qid),
          into: %{},
          do: {qid, a}

    Map.put(h, "answers", answers)
  end

  def reconcile("comparison", _old, new, h) do
    keep = ids(new["criteria"])
    Map.update(h, "weights", %{}, &Map.take(&1, keep))
  end

  def reconcile("round", _old, new, h) do
    keep = ids(new["statuses"] || [])
    Map.update(h, "statuses", %{}, &Map.take(&1, keep))
  end

  # An edited draft must be approved again.
  def reconcile("draft_comments", old, new, h) do
    old_c = Map.new(old["comments"], &{&1["id"], Map.delete(&1, "posted_url")})
    new_c = Map.new(new["comments"], &{&1["id"], Map.delete(&1, "posted_url")})

    Map.update(h, "decisions", %{}, fn decisions ->
      for {id, d} <- decisions, Map.get(old_c, id) == Map.get(new_c, id), into: %{}, do: {id, d}
    end)
  end

  def reconcile("findings", _old, new, h) do
    keep = ids(new["findings"])
    Map.update(h, "marks", %{}, &Map.take(&1, keep))
  end

  def reconcile("diagram", old, new, h) do
    if old["source"] == new["source"], do: h, else: Map.drop(h, ["error"])
  end

  def reconcile(_kind, _old, _new, h), do: h

  ## Examples

  @doc "Example data for each kind, shown in the catalog and on the design-system page."
  def example("prose"),
    do: %{
      "text" => "Agents write **markdown** here when no other widget fits:\n\n- short\n- concrete"
    }

  def example("callout"),
    do: %{
      "tone" => "risk",
      "title" => "The reset drops every goal",
      "body" => "Save the board before deploying."
    }

  def example("requirement"),
    do: %{
      "id" => "R3",
      "pattern" => "event",
      "trigger" => "the human clicks Confirm on a requirement card",
      "system" => "board",
      "response" => "show the requirement as confirmed"
    }

  def example("examples"),
    do: %{
      "title" => "Seat limits",
      "columns" => ["Plan", "Seats"],
      "expected_label" => "Invite",
      "rows" => [
        %{"id" => "r1", "values" => ["free", "1"], "expected" => "allowed"},
        %{
          "id" => "r2",
          "values" => ["free", "2"],
          "expected" => "rejected: upgrade to add seats"
        },
        %{"id" => "r3", "values" => ["pro", "2"], "expected" => "allowed"}
      ]
    }

  def example("glossary_term"),
    do: %{
      "term" => "Listening session",
      "meaning" => "The live agent session that receives anchored comments for a goal or task.",
      "limits" =>
        "Pi, Codex, and Copilot CLI sessions hear it at their next turn; no idle session is woken."
    }

  def example("decision"),
    do: %{
      "decision" => "Widgets are structured data from a fixed catalog",
      "reason" => "Jarvis can validate them, draw them safely, and anchor comments to each part.",
      "alternatives" => ["Markdown with special code blocks", "Agent-written HTML"]
    }

  def example("diagram"),
    do: %{
      "title" => "How a comment reaches the agent",
      "source" =>
        "flowchart LR\n  H[Human] -->|comments on a part| J(Jarvis)\n  J -->|delivers next turn| A[Agent session]\n  A -->|updates widget| J\n  A -->|replies| J"
    }

  def example("architecture"),
    do: %{
      "title" => "Jarvis",
      "groups" => [
        %{"id" => "server", "label" => "Jarvis server"},
        %{"id" => "dev", "label" => "Developer machine"}
      ],
      "nodes" => [
        %{
          "id" => "human",
          "label" => "Human",
          "kind" => "person",
          "description" => "Watches the board in a browser."
        },
        %{
          "id" => "pi",
          "label" => "pi + extension",
          "kind" => "external",
          "group" => "dev",
          "description" => "Agent harness; polls for comments."
        },
        %{
          "id" => "live",
          "label" => "LiveView pages",
          "kind" => "component",
          "group" => "server"
        },
        %{"id" => "api", "label" => "Agent API", "kind" => "service", "group" => "server"},
        %{"id" => "db", "label" => "PostgreSQL", "kind" => "datastore", "group" => "server"}
      ],
      "edges" => [
        %{"id" => "e1", "from" => "human", "to" => "live", "label" => "comments"},
        %{"id" => "e2", "from" => "pi", "to" => "api", "label" => "tools"},
        %{"id" => "e3", "from" => "live", "to" => "db"},
        %{"id" => "e4", "from" => "api", "to" => "db"}
      ],
      "tour" => [
        %{
          "id" => "s1",
          "title" => "The human comments",
          "narration" => "A comment on a part is stored with its anchor.",
          "nodes" => ["human", "live", "db"],
          "edges" => ["e1", "e3"]
        },
        %{
          "id" => "s2",
          "title" => "The agent hears the comment",
          "narration" =>
            "At the start of its next turn, the listening session receives pending comments.",
          "nodes" => ["pi", "api"],
          "edges" => ["e2"]
        }
      ]
    }

  def example("quiz"),
    do: %{
      "mode" => "self_study",
      "questions" => [
        %{
          "id" => "q1",
          "prompt" => "Who moves a Feature task out of Requirements?",
          "type" => "single",
          "options" => [
            %{
              "id" => "a",
              "text" => "The agent running /specify",
              "explanation" =>
                "The agent writes requirements, but approving them is the human's decision."
            },
            %{
              "id" => "b",
              "text" => "The human, once every requirement is confirmed",
              "correct" => true,
              "explanation" => "approve requirements is a human transition with that condition."
            }
          ]
        },
        %{
          "id" => "q2",
          "prompt" => "In one sentence: why are widgets structured data?",
          "type" => "text",
          "model_answer" =>
            "So Jarvis can validate and draw them safely and anchor comments to each part."
        }
      ]
    }

  def example("comparison"),
    do: %{
      "criteria" => [
        %{"id" => "fit", "label" => "Fits LiveView", "weight" => 3},
        %{"id" => "setup", "label" => "Setup cost", "weight" => 2},
        %{"id" => "power", "label" => "Expressive power", "weight" => 1}
      ],
      "options" => [
        %{
          "id" => "mermaid",
          "label" => "Mermaid via hook",
          "scores" => %{"fit" => 4, "setup" => 5, "power" => 3}
        },
        %{
          "id" => "flow",
          "label" => "LiveFlow",
          "scores" => %{"fit" => 5, "setup" => 3, "power" => 4},
          "notes" => %{"setup" => "young library"}
        },
        %{
          "id" => "react",
          "label" => "React Flow island",
          "scores" => %{"fit" => 2, "setup" => 1, "power" => 5}
        }
      ],
      "recommended" => "mermaid"
    }

  def example("sources"),
    do: %{
      "sources" => [
        %{
          "id" => "mayer",
          "title" => "Mayer, Multimedia Learning (2020)",
          "quote" =>
            "People learn better when corresponding words and pictures are presented near rather than far from each other."
        },
        %{
          "id" => "victor",
          "title" => "Bret Victor, Explorable Explanations",
          "url" => "https://worrydream.com/ExplorableExplanations/"
        }
      ],
      "claims" => [
        %{
          "id" => "c1",
          "text" => "Labels belong on the diagram, not in a legend.",
          "sources" => ["mayer"]
        },
        %{
          "id" => "c2",
          "text" => "Readers understand more when they can manipulate a model.",
          "sources" => ["victor"]
        },
        %{"id" => "c3", "text" => "Everyone prefers dark mode.", "sources" => []}
      ]
    }

  def example("walkthrough"),
    do: %{
      "title" => "How a widget is saved",
      "steps" => [
        %{
          "id" => "s1",
          "path" => "lib/jarvis/planning/catalog.ex",
          "lines" => "1-5",
          "language" => "elixir",
          "code" =>
            "def validate(kind, data) when is_map(data) do\n  {normalized, errors} = check_object(fields(kind), stringify(data), \"\")\nend",
          "narration" => "Data is checked against the kind's fields first."
        },
        %{
          "id" => "s2",
          "path" => "lib/jarvis/planning.ex",
          "language" => "elixir",
          "code" => "Repo.transact(fn -> apply_ops(scope, owner, ops) end)",
          "narration" => "All operations of one call succeed or fail together."
        }
      ]
    }

  def example("findings"),
    do: %{
      "findings" => [
        %{
          "id" => "f1",
          "severity" => "major",
          "path" => "lib/jarvis/planning.ex",
          "line" => "120",
          "explanation" => "The move is not checked against the gate quiz.",
          "suggestion" => "Check gate quizzes in move_task/3."
        },
        %{
          "id" => "f2",
          "severity" => "nit",
          "path" => "README.md",
          "explanation" => "Typo in the tools table."
        }
      ]
    }

  def example("discussion"),
    do: %{
      "status" => "read",
      "items" => [
        %{
          "id" => "i1",
          "type" => "thread",
          "author" => "maria",
          "path" => "lib/jarvis/planning.ex",
          "line" => "120",
          "resolved" => false,
          "body" => "Should this check the gate quiz too?"
        },
        %{
          "id" => "i2",
          "type" => "review",
          "author" => "tom",
          "state" => "changes_requested",
          "body" => "Needs tests."
        },
        %{
          "id" => "i3",
          "type" => "thread",
          "author" => "maria",
          "path" => "README.md",
          "line" => "4",
          "resolved" => true,
          "body" => "Typo."
        },
        %{
          "id" => "i4",
          "type" => "conversation",
          "author" => "tom",
          "body" => "Thanks for the quick turnaround."
        }
      ]
    }

  def example("round"),
    do: %{
      "number" => 2,
      "head" => "b7c9e21",
      "previous_head" => "a41f03d",
      "commits" => [
        %{"id" => "c1", "sha" => "b7c9e21", "subject" => "Check gate quizzes in move_task"}
      ],
      "statuses" => [
        %{
          "id" => "s1",
          "finding" => "f1",
          "status" => "resolved",
          "location" => "lib/jarvis/planning.ex:131",
          "reason" => "move_task/3 now checks the gate quiz."
        },
        %{
          "id" => "s2",
          "finding" => "f2",
          "status" => "open",
          "location" => "README.md:12",
          "reason" => "The typo is still there."
        },
        %{
          "id" => "s3",
          "finding" => "f3",
          "status" => "location_gone",
          "old_location" => "lib/old.ex:9",
          "reason" => "The file was deleted; I cannot tell if the issue went with it."
        }
      ]
    }

  def example("draft_comments"),
    do: %{
      "head" => "b7c9e21",
      "comments" => [
        %{
          "id" => "c1",
          "path" => "lib/jarvis/planning.ex",
          "line" => "122",
          "hunk" =>
            "@@ -118,5 +118,6 @@ defmodule Jarvis.Planning do\n   def move_task(scope, task, name) do\n     with {:ok, t} <- fetch(task) do\n+      t = do_move(t, name)\n       {:ok, t}\n     end\n   end",
          "body" =>
            "This skips the gate quiz check; `move_task/3` should refuse while the quiz is open."
        },
        %{
          "id" => "c2",
          "path" => "lib/jarvis/planning.ex",
          "line" => "300",
          "hunk" => "@@ -118,3 +118,4 @@\n   def a, do: 1\n+  def b, do: 2",
          "body" => "Line 300 is not in this hunk, so this one is flagged."
        }
      ]
    }
end
