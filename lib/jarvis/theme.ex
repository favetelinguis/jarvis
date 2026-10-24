defmodule Jarvis.Theme do
  @moduledoc """
  The global theme, derived from three brand colors (primary, secondary,
  accent) the human sets on the settings page.

  Each brand color is darkened for light mode and lightened for dark mode
  until text in that color reaches a contrast ratio of 4.5:1 against the page
  background, and gets a `-content` color (black or white, whichever contrasts
  more) for text on top of it. While no brand colors are saved, the default
  brand colors are used.
  """

  import Ecto.Query

  alias Jarvis.{Repo, Setting}

  @pubsub Jarvis.PubSub
  @topic "theme"
  @key "theme"

  @names ~w(primary secondary accent)
  @defaults %{"primary" => "#4f5bd5", "secondary" => "#5b6b82", "accent" => "#d9822b"}

  # Page backgrounds (base-100) of the light and dark daisyUI themes in app.css.
  @backgrounds %{light: {0.98, 0.0, 0.0}, dark: {0.3033, 0.016, 252.42}}
  # Body text (base-content) of the same themes.
  @texts %{light: {0.21, 0.006, 285.885}, dark: {0.97807, 0.029, 256.847}}

  @min_contrast 4.5

  def names, do: @names
  def defaults, do: @defaults

  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "The saved brand colors, or the defaults, as `%{\"primary\" => \"#rrggbb\", ...}`."
  def current do
    case Repo.get(Setting, @key) do
      %Setting{value: colors} -> Map.merge(@defaults, colors)
      nil -> @defaults
    end
  end

  @doc "True when the human saved brand colors."
  def custom?, do: Repo.exists?(from s in Setting, where: s.key == ^@key)

  @doc """
  Validates brand colors: `{:ok, colors}` with each as `#rrggbb`, or
  `{:error, %{name => message}}` naming every invalid one.
  """
  def validate(params) do
    {colors, errors} =
      Enum.reduce(@names, {%{}, %{}}, fn name, {colors, errors} ->
        case parse_hex(Map.get(params, name, "")) do
          {:ok, rgb} -> {Map.put(colors, name, to_hex(rgb)), errors}
          :error -> {colors, Map.put(errors, name, "not a valid color; use #rgb or #rrggbb")}
        end
      end)

    if errors == %{}, do: {:ok, colors}, else: {:error, errors}
  end

  @doc "Saves brand colors and switches every open page to the new theme."
  def save(params) do
    with {:ok, colors} <- validate(params) do
      Repo.insert!(%Setting{key: @key, value: colors},
        on_conflict: {:replace, [:value, :updated_at]},
        conflict_target: :key
      )

      broadcast()
      {:ok, colors}
    end
  end

  @doc "Goes back to the default theme."
  def reset do
    Repo.delete_all(from s in Setting, where: s.key == ^@key)
    broadcast()
    :ok
  end

  defp broadcast, do: Phoenix.PubSub.broadcast(@pubsub, @topic, {:theme, css(current())})

  @doc """
  The CSS that applies brand colors to both color modes. With `scope`, a CSS
  selector, it applies them only inside that element (for previews).
  """
  def css(colors, scope \\ nil)

  def css(colors, nil) do
    light = vars(colors, :light)
    dark = vars(colors, :dark)

    """
    :root,[data-theme=light]{#{light}}
    [data-theme=dark]{#{dark}}
    @media (prefers-color-scheme: dark){:root:not([data-theme=light]){#{dark}}}
    """
  end

  def css(colors, scope) do
    "#{scope}{#{vars(colors, :light)}}\n[data-theme=dark] #{scope}{#{vars(colors, :dark)}}\n"
  end

  defp vars(colors, mode) do
    Enum.map_join(palette(colors, mode), "", fn {name, hex} -> "--color-#{name}:#{hex};" end)
  end

  @doc """
  The derived colors of a mode as `[{css name, "#rrggbb"}]`: each brand color
  adjusted for contrast against the background, and its content color.
  """
  def palette(colors, mode) do
    background = oklch_to_rgb(@backgrounds[mode])

    Enum.flat_map(@names, fn name ->
      {:ok, rgb} = parse_hex(colors[name])
      color = readable(rgb, background, mode)
      [{name, to_hex(color)}, {"#{name}-content", to_hex(content_for(color))}]
    end)
  end

  @doc """
  Every text and background pair of the theme in a mode, as
  `{label, foreground rgb, background rgb}`, for checking contrast.
  """
  def text_pairs(colors, mode) do
    background = oklch_to_rgb(@backgrounds[mode])
    body = oklch_to_rgb(@texts[mode])

    derived =
      Map.new(palette(colors, mode), fn {name, hex} -> {name, elem(parse_hex(hex), 1)} end)

    [{"base-content on base-100", body, background}] ++
      Enum.flat_map(@names, fn name ->
        [
          {"#{name} on base-100", derived[name], background},
          {"#{name}-content on #{name}", derived["#{name}-content"], derived[name]}
        ]
      end)
  end

  # Moves the color toward black (light mode) or white (dark mode) until it reads on the background.
  defp readable(rgb, background, mode) do
    target = if mode == :light, do: {0.0, 0.0, 0.0}, else: {1.0, 1.0, 1.0}

    Enum.reduce_while(0..40, rgb, fn step, _ ->
      color = mix(rgb, target, step / 40)

      if contrast(color, background) >= @min_contrast,
        do: {:halt, color},
        else: {:cont, color}
    end)
  end

  defp content_for(color) do
    black = {0.0, 0.0, 0.0}
    white = {1.0, 1.0, 1.0}
    if contrast(black, color) >= contrast(white, color), do: black, else: white
  end

  ## Color math (sRGB components 0.0-1.0)

  @doc "WCAG contrast ratio of two sRGB colors."
  def contrast(a, b) do
    {hi, lo} =
      Enum.min_max_by([luminance(a), luminance(b)], & &1) |> then(fn {l, h} -> {h, l} end)

    (hi + 0.05) / (lo + 0.05)
  end

  defp luminance({r, g, b}) do
    [r, g, b] = Enum.map([r, g, b], &linear/1)
    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  defp linear(c) when c <= 0.04045, do: c / 12.92
  defp linear(c), do: :math.pow((c + 0.055) / 1.055, 2.4)

  defp gamma(c) when c <= 0.0031308, do: 12.92 * c
  defp gamma(c), do: 1.055 * :math.pow(c, 1 / 2.4) - 0.055

  defp mix({r1, g1, b1}, {r2, g2, b2}, t),
    do: {r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t}

  @doc "Converts OKLCH (lightness 0-1, chroma, hue in degrees) to sRGB."
  def oklch_to_rgb({l, c, h}) do
    rad = h * :math.pi() / 180
    a = c * :math.cos(rad)
    b = c * :math.sin(rad)

    l_ = :math.pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
    m_ = :math.pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
    s_ = :math.pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)

    r = 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
    g = -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
    bl = -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_

    {clamp(gamma(max(r, 0.0))), clamp(gamma(max(g, 0.0))), clamp(gamma(max(bl, 0.0)))}
  end

  defp clamp(v), do: v |> max(0.0) |> min(1.0)

  @doc "Parses `#rgb` or `#rrggbb` into sRGB components."
  def parse_hex(value) when is_binary(value) do
    case String.trim(value) |> String.downcase() do
      "#" <> <<r::binary-1, g::binary-1, b::binary-1>> ->
        parse_hex("#" <> r <> r <> g <> g <> b <> b)

      "#" <> <<r::binary-2, g::binary-2, b::binary-2>> ->
        channels([r, g, b])

      _ ->
        :error
    end
  end

  def parse_hex(_), do: :error

  defp channels(parts) do
    parsed = Enum.map(parts, &Integer.parse(&1, 16))

    if Enum.all?(parsed, &match?({_, ""}, &1)) do
      [r, g, b] = Enum.map(parsed, fn {v, ""} -> v / 255 end)
      {:ok, {r, g, b}}
    else
      :error
    end
  end

  def to_hex({r, g, b}) do
    "#" <>
      Enum.map_join(
        [r, g, b],
        &(round(&1 * 255)
          |> Integer.to_string(16)
          |> String.pad_leading(2, "0")
          |> String.downcase())
      )
  end
end
