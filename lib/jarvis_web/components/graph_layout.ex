defmodule JarvisWeb.GraphLayout do
  @moduledoc """
  Lays out graphs for drawing on the server, so the browser only pans and zooms.

  - `architecture/1`: nodes in columns by their longest path from a source
    (edges flow left to right) and in one horizontal band per group, so no two
    nodes overlap and every node sits inside its group's box.
  - `lifecycle/2`: the steps of a lifecycle in a row, forward transitions as
    arcs above, transitions back to an earlier step as arcs below.
  """

  @node_w 176
  @node_h 64
  @col_gap 84
  @row_gap 20
  @band_pad 18
  @band_label 22
  @band_gap 28

  @doc "Positions for an architecture graph's nodes, group boxes, and edge paths."
  def architecture(data) do
    nodes = data["nodes"]
    edges = data["edges"] || []
    layers = layers(nodes, edges)

    declared = data["groups"] || []
    used = nodes |> Enum.map(& &1["group"]) |> Enum.uniq()

    bands =
      Enum.filter([nil | Enum.map(declared, & &1["id"])], &(&1 in used))

    {positions, boxes, height} =
      Enum.reduce(bands, {%{}, [], 0}, fn group, {positions, boxes, y} ->
        members = Enum.filter(nodes, &(&1["group"] == group))
        top = if group, do: y + @band_pad + @band_label, else: y

        {placed, rows} =
          members
          |> Enum.group_by(&layers[&1["id"]])
          |> Enum.reduce({%{}, 0}, fn {layer, in_layer}, {acc, rows} ->
            acc =
              in_layer
              |> Enum.with_index()
              |> Enum.reduce(acc, fn {n, row}, acc ->
                Map.put(acc, n["id"], %{
                  x: @band_pad + layer * (@node_w + @col_gap),
                  y: top + row * (@node_h + @row_gap),
                  w: @node_w,
                  h: @node_h
                })
              end)

            {acc, max(rows, length(in_layer))}
          end)

        band_h = rows * (@node_h + @row_gap) - @row_gap
        bottom = top + band_h + if(group, do: @band_pad, else: 0)

        boxes =
          if group do
            xs = Enum.map(placed, fn {_, p} -> p.x end)
            label = Enum.find(declared, &(&1["id"] == group))["label"]

            [
              %{
                id: group,
                label: label,
                x: Enum.min(xs) - @band_pad,
                y: y,
                w: Enum.max(xs) - Enum.min(xs) + @node_w + 2 * @band_pad,
                h: bottom - y
              }
              | boxes
            ]
          else
            boxes
          end

        {Map.merge(positions, placed), boxes, bottom + @band_gap}
      end)

    width =
      positions |> Map.values() |> Enum.map(&(&1.x + &1.w)) |> Enum.max(fn -> 0 end)

    width = max(width, boxes |> Enum.map(&(&1.x + &1.w)) |> Enum.max(fn -> 0 end)) + @band_pad

    %{
      width: width,
      height: max(height - @band_gap, @node_h),
      nodes: positions,
      groups: Enum.reverse(boxes),
      edges: Enum.map(edges, &edge_path(&1, positions))
    }
  end

  # Longest path from a source over the edges that are not cycle-closing, then compacted.
  defp layers(nodes, edges) do
    ids = Enum.map(nodes, & &1["id"])
    forward = drop_back_edges(ids, edges)
    start = Map.new(ids, &{&1, 0})

    layers =
      Enum.reduce(1..max(length(ids), 1), start, fn _, acc ->
        Enum.reduce(forward, acc, fn e, acc ->
          if Map.has_key?(acc, e["from"]) and Map.has_key?(acc, e["to"]),
            do: Map.update!(acc, e["to"], &max(&1, acc[e["from"]] + 1)),
            else: acc
        end)
      end)

    compact =
      layers |> Map.values() |> Enum.uniq() |> Enum.sort() |> Enum.with_index() |> Map.new()

    Map.new(layers, fn {id, layer} -> {id, compact[layer]} end)
  end

  # A depth-first walk; an edge to a node still on the walk's stack closes a cycle.
  defp drop_back_edges(ids, edges) do
    out = Enum.group_by(edges, & &1["from"])

    {_visited, _stack, back} =
      Enum.reduce(ids, {MapSet.new(), MapSet.new(), []}, fn id, state -> walk(id, out, state) end)

    Enum.reject(edges, &(&1 in back or &1["from"] == &1["to"]))
  end

  defp walk(id, out, {visited, stack, back} = state) do
    if MapSet.member?(visited, id) do
      state
    else
      state = {MapSet.put(visited, id), MapSet.put(stack, id), back}

      {visited, stack, back} =
        Enum.reduce(Map.get(out, id, []), state, fn edge, {_, stack, back} = acc ->
          if MapSet.member?(stack, edge["to"]),
            do: put_elem(acc, 2, [edge | back]),
            else: walk(edge["to"], out, acc) |> then(&put_elem(&1, 1, stack))
        end)

      {visited, MapSet.delete(stack, id), back}
    end
  end

  defp edge_path(edge, positions) do
    a = positions[edge["from"]]
    b = positions[edge["to"]]

    {x1, y1, x2, y2, d} =
      cond do
        b.x > a.x ->
          {x1, y1} = {a.x + a.w, a.y + a.h / 2}
          {x2, y2} = {b.x, b.y + b.h / 2}
          mid = (x1 + x2) / 2
          {x1, y1, x2, y2, "M#{x1},#{y1} C#{mid},#{y1} #{mid},#{y2} #{x2},#{y2}"}

        b.x < a.x ->
          {x1, y1} = {a.x, a.y + a.h / 2}
          {x2, y2} = {b.x + b.w, b.y + b.h / 2}
          mid = (x1 + x2) / 2
          {x1, y1, x2, y2, "M#{x1},#{y1} C#{mid},#{y1} #{mid},#{y2} #{x2},#{y2}"}

        b.y >= a.y ->
          {x1, y1} = {a.x + a.w / 2, a.y + a.h}
          {x2, y2} = {b.x + b.w / 2, b.y}
          {x1, y1, x2, y2, "M#{x1},#{y1} L#{x2},#{y2}"}

        true ->
          {x1, y1} = {a.x + a.w / 2, a.y}
          {x2, y2} = {b.x + b.w / 2, b.y + b.h}
          {x1, y1, x2, y2, "M#{x1},#{y1} L#{x2},#{y2}"}
      end

    %{
      id: edge["id"],
      from: edge["from"],
      to: edge["to"],
      label: edge["label"],
      d: d,
      lx: (x1 + x2) / 2,
      ly: (y1 + y2) / 2
    }
  end

  @step_w 132
  @step_h 52
  @step_gap 124
  @arc_room 46

  @doc """
  Positions for a lifecycle: `steps` as `[{key, label, hint}]`, `transitions`
  as maps with `from`, `to`, and `name`.
  """
  def lifecycle(steps, transitions) do
    index = steps |> Enum.map(&elem(&1, 0)) |> Enum.with_index() |> Map.new()
    top = @arc_room + 14

    boxes =
      Map.new(steps, fn {key, _, _} ->
        {key, %{x: index[key] * (@step_w + @step_gap), y: top, w: @step_w, h: @step_h}}
      end)

    arcs =
      Enum.map(transitions, fn t ->
        a = boxes[t.from]
        b = boxes[t.to]
        span = abs(index[t.to] - index[t.from])

        cond do
          index[t.to] == index[t.from] + 1 ->
            {x1, y} = {a.x + a.w, a.y + a.h / 2}
            x2 = b.x
            %{t: t, d: "M#{x1},#{y} L#{x2 - 2},#{y}", lx: (x1 + x2) / 2, ly: y - 8, dir: :forward}

          index[t.to] > index[t.from] ->
            {x1, x2, y} = {a.x + a.w / 2, b.x + b.w / 2, a.y}
            lift = min(@arc_room, 18 + span * 10)

            %{
              t: t,
              d: "M#{x1},#{y} C#{x1},#{y - lift} #{x2},#{y - lift} #{x2},#{y - 2}",
              lx: (x1 + x2) / 2,
              ly: y - lift + 4,
              dir: :forward
            }

          true ->
            {x1, x2, y} = {a.x + a.w / 2 - 12, b.x + b.w / 2 + 12, a.y + a.h}
            drop = min(@arc_room, 18 + span * 10)

            %{
              t: t,
              d: "M#{x1},#{y} C#{x1},#{y + drop} #{x2},#{y + drop} #{x2},#{y + 2}",
              lx: (x1 + x2) / 2,
              ly: y + drop + 12,
              dir: :back
            }
        end
      end)

    %{
      width: length(steps) * (@step_w + @step_gap) - @step_gap,
      height: top + @step_h + @arc_room + 26,
      steps: boxes,
      arcs: arcs
    }
  end
end
