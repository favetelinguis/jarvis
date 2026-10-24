defmodule JarvisWeb.ThemeHook do
  @moduledoc "Gives every LiveView the current theme's CSS and keeps it current when the human saves new brand colors."
  import Phoenix.Component
  import Phoenix.LiveView

  alias Jarvis.Theme

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Theme.subscribe()

    {:cont,
     socket
     |> assign(:theme_css, Theme.css(Theme.current()))
     |> attach_hook(:theme, :handle_info, fn
       {:theme, css}, socket -> {:halt, assign(socket, :theme_css, css)}
       _other, socket -> {:cont, socket}
     end)}
  end
end
