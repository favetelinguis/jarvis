defmodule JarvisWeb.DisplaySettingsTest do
  @moduledoc "Lager 4: the reader's display settings (Floe)."
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "the browser logic applies, keeps, resets, and falls back (node --test)" do
    {out, status} =
      System.cmd("node", ["--test", "test/js/display.test.mjs"], stderr_to_stdout: true)

    assert status == 0, out
  end

  test "settings, a how-to page, offers exactly the five settings and their values", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, ~p"/settings")
    assert has_element?(view, "#page-form [data-form=how_to]")
    assert has_element?(view, "ol#display-steps li")
    assert has_element?(view, "#display-form[phx-hook=DisplaySettings][phx-update=ignore]")

    offered =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#display-form input[type=radio]")
      |> Enum.map(&{hd(LazyHTML.attribute(&1, "name")), hd(LazyHTML.attribute(&1, "value"))})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    assert offered == %{
             "textSize" => ~w(100 125 150 200),
             "leading" => ~w(normal increased),
             "theme" => ~w(light dark contrast),
             "motion" => ~w(on reduced),
             "density" => ~w(airy compact)
           }

    assert has_element?(view, "#display-reset", "Reset to defaults")
  end

  test "the values the page offers are the ones the script accepts" do
    js = File.read!("assets/js/display.js")

    for {key, values} <- [
          textSize: ~w(100 125 150 200),
          leading: ~w(normal increased),
          theme: ~w(light dark contrast),
          motion: ~w(on reduced),
          density: ~w(airy compact)
        ] do
      list = Enum.map_join(values, ", ", &~s("#{&1}"))
      assert js =~ "#{key}: [#{list}]", "display.js does not offer #{key}: #{list}"
    end
  end
end
