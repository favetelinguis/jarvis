defmodule Jarvis.ThemeTest do
  use Jarvis.DataCase, async: false

  alias Jarvis.Theme

  @themes [
    Theme.defaults(),
    %{"primary" => "#0b5fff", "secondary" => "#1f2937", "accent" => "#f59e0b"},
    %{"primary" => "#ffff00", "secondary" => "#ffffff", "accent" => "#000000"}
  ]

  test "every text and background pair reaches 4.5:1 in both modes, whatever the brand colors" do
    for colors <- @themes,
        mode <- [:light, :dark],
        {label, fg, bg} <- Theme.text_pairs(colors, mode) do
      assert Theme.contrast(fg, bg) >= 4.5,
             "#{label} in #{mode} mode with #{inspect(colors)} has contrast #{Theme.contrast(fg, bg)}"
    end
  end

  test "validate accepts #rgb and #rrggbb and names every invalid color" do
    assert {:ok, %{"primary" => "#aabbcc", "secondary" => "#112233", "accent" => "#ffffff"}} =
             Theme.validate(%{"primary" => "#ABC", "secondary" => "#112233", "accent" => "#fff"})

    assert {:error, %{"primary" => _, "accent" => _} = errors} =
             Theme.validate(%{"primary" => "blueish", "secondary" => "#112233", "accent" => ""})

    refute Map.has_key?(errors, "secondary")
  end

  test "the default theme is used until colors are saved, and again after a reset" do
    refute Theme.custom?()
    assert Theme.current() == Theme.defaults()

    assert {:ok, _} =
             Theme.save(%{
               "primary" => "#0b5fff",
               "secondary" => "#1f2937",
               "accent" => "#f59e0b"
             })

    assert Theme.custom?()
    assert Theme.current()["primary"] == "#0b5fff"

    Theme.reset()
    assert Theme.current() == Theme.defaults()
  end

  test "an invalid save keeps the current theme" do
    {:ok, _} =
      Theme.save(%{"primary" => "#0b5fff", "secondary" => "#1f2937", "accent" => "#f59e0b"})

    assert {:error, %{"primary" => _}} =
             Theme.save(%{
               "primary" => "blueish",
               "secondary" => "#1f2937",
               "accent" => "#f59e0b"
             })

    assert Theme.current()["primary"] == "#0b5fff"
  end

  test "saving tells open pages" do
    Theme.subscribe()

    {:ok, _} =
      Theme.save(%{"primary" => "#0b5fff", "secondary" => "#1f2937", "accent" => "#f59e0b"})

    assert_receive {:theme, css}
    assert css =~ "--color-primary"
  end

  test "css derives the same colors for light and dark scoped to a selector" do
    css = Theme.css(Theme.defaults(), "#preview")
    assert css =~ "#preview{--color-primary:"
    assert css =~ "[data-theme=dark] #preview{"
  end
end
