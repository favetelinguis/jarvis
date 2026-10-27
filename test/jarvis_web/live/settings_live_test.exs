defmodule JarvisWeb.SettingsLiveTest do
  use JarvisWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Jarvis.Theme

  @good %{"primary" => "#0b5fff", "secondary" => "#1f2937", "accent" => "#f59e0b"}

  test "the language defaults to Swedish and a change is saved", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings")
    assert has_element?(view, "#language option[value=sv][selected]")
    view |> form("#language-form", language: "en") |> render_change()
    assert Jarvis.Language.current() == "en"
  end

  test "previews edited colors without saving them", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings")
    view |> form("#brand-form", colors: @good) |> render_change()
    assert render(view) =~ "#preview{--color-primary:"
    refute Theme.custom?()
  end

  test "saving applies the theme to the page and to pages already open", %{conn: conn} do
    {:ok, other, _} = live(conn, ~p"/design-system")
    {:ok, view, _} = live(conn, ~p"/settings")
    {"primary", derived} = @good |> Theme.palette(:light) |> hd()
    refute has_element?(other, "#brand-theme", derived)

    view |> form("#brand-form", colors: @good) |> render_submit()
    assert Theme.current()["primary"] == "#0b5fff"
    assert has_element?(other, "#brand-theme", "--color-primary:#{derived}")
    assert has_element?(view, "#reset-colors:not([disabled])")
  end

  test "an invalid color is named and the current theme stays", %{conn: conn} do
    {:ok, _} = Theme.save(@good)
    {:ok, view, _} = live(conn, ~p"/settings")
    view |> form("#brand-form", colors: %{@good | "primary" => "blueish"}) |> render_submit()
    assert has_element?(view, "#error-primary", "Primary: not a valid color")
    assert Theme.current()["primary"] == "#0b5fff"
  end

  test "reset goes back to the default theme", %{conn: conn} do
    {:ok, _} = Theme.save(@good)
    {:ok, view, _} = live(conn, ~p"/settings")
    view |> element("#reset-colors") |> render_click()
    assert Theme.current() == Theme.defaults()
  end

  test "shows the contrast of every text color, all at least 4.5", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/settings")

    view
    |> form("#brand-form",
      colors: %{"primary" => "#ffff00", "secondary" => "#ffffff", "accent" => "#000000"}
    )
    |> render_change()

    assert has_element?(view, "#contrast-table tr")
    refute has_element?(view, "#contrast-table .text-error")
  end

  describe "integrations panel" do
    test "shows a row per agent and installs and uninstalls pi", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings")
      _ = render_async(view)
      for agent <- ~w(pi codex copilot), do: assert(has_element?(view, "#integration-#{agent}"))
      assert has_element?(view, "#integration-state-pi", "Not installed")
      assert has_element?(view, "#uninstall-pi[disabled]")

      view |> form("#integration-form-pi") |> render_submit()
      assert has_element?(view, "#integration-state-pi", "Installed")
      assert has_element?(view, "#integration-activation-pi", "/reload")
      refute has_element?(view, "#uninstall-pi[disabled]")

      view |> element("#uninstall-pi") |> render_click()
      assert has_element?(view, "#integration-state-pi", "Not installed")
    end

    test "a model and effort set before Install reach the subagent, and a change updates it", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/settings")
      _ = render_async(view)

      for name <- ~w(jarvis-scout jarvis-design-reviewer jarvis-impl-reviewer) do
        assert has_element?(view, "#subagent-model-codex-#{name}")
        assert has_element?(view, "#subagent-effort-codex-#{name}")
      end

      set = fn model, effort ->
        view
        |> form("#integration-form-codex",
          subagents: %{"jarvis-scout" => %{"model" => model, "effort" => effort}}
        )
        |> render_submit()
      end

      set.("gpt-5.4", "high")
      assert has_element?(view, ~s(#subagent-model-codex-jarvis-scout[value="gpt-5.4"]))

      assert has_element?(
               view,
               "#subagent-effort-codex-jarvis-scout option[value=high][selected]"
             )

      set.("gpt-5.5", "low")
      assert has_element?(view, ~s(#subagent-model-codex-jarvis-scout[value="gpt-5.5"]))
      assert has_element?(view, "#subagent-effort-codex-jarvis-scout option[value=low][selected]")
      assert has_element?(view, "#integration-state-codex", "Installed")

      set.("not a model", "low")
      assert has_element?(view, "#integration-error-codex", "jarvis-scout")
      assert has_element?(view, ~s(#subagent-model-codex-jarvis-scout[value="gpt-5.5"]))

      view |> element("#uninstall-codex") |> render_click()
    end
  end
end
