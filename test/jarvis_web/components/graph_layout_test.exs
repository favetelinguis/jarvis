defmodule JarvisWeb.GraphLayoutTest do
  use ExUnit.Case, async: true

  alias Jarvis.Planning.{Catalog, TaskType}
  alias JarvisWeb.GraphLayout

  defp overlap?(a, b),
    do: a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h

  test "architecture: no two nodes overlap and every node sits inside its group" do
    {:ok, data} = Catalog.validate("architecture", Catalog.example("architecture"))
    layout = GraphLayout.architecture(data)

    boxes = Map.values(layout.nodes)
    for a <- boxes, b <- boxes, a != b, do: refute(overlap?(a, b))

    groups = Map.new(layout.groups, &{&1.id, &1})

    for n <- data["nodes"], n["group"] do
      node = layout.nodes[n["id"]]
      g = groups[n["group"]]
      assert node.x >= g.x and node.y >= g.y
      assert node.x + node.w <= g.x + g.w and node.y + node.h <= g.y + g.h
    end

    assert length(layout.edges) == length(data["edges"])
  end

  test "architecture: edges flow left to right and cycles stay finite" do
    {:ok, data} =
      Catalog.validate("architecture", %{
        "nodes" => for(id <- ~w(a b c), do: %{"id" => id, "label" => id, "kind" => "service"}),
        "edges" => [
          %{"from" => "a", "to" => "b"},
          %{"from" => "b", "to" => "c"},
          %{"from" => "c", "to" => "a"}
        ]
      })

    layout = GraphLayout.architecture(data)
    assert layout.nodes["a"].x < layout.nodes["b"].x
    assert layout.nodes["b"].x < layout.nodes["c"].x
  end

  test "lifecycle: forward transitions are drawn above, going back below" do
    layout = GraphLayout.lifecycle(TaskType.steps(:feature), TaskType.transitions(:feature))
    back = Enum.filter(layout.arcs, &(&1.dir == :back))

    assert Enum.map(back, & &1.t.name) |> Enum.sort() == [
             "request changes",
             "requirements question"
           ]

    assert map_size(layout.steps) == 5
  end
end
