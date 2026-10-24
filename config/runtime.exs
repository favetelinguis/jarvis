import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/jarvis start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :jarvis, JarvisWeb.Endpoint, server: true
end

port = String.to_integer(System.get_env("PORT", "4000"))

config :jarvis, JarvisWeb.Endpoint, http: [port: port]

if config_env() == :dev do
  # Reload browser tabs when matching files change. On Linux the file watcher
  # needs inotify-tools; without it, poll just the watched directories instead
  # of failing with an error at startup.
  if match?({:unix, :linux}, :os.type()) and is_nil(System.find_executable("inotifywait")) do
    config :phoenix_live_reload,
      backend: :fs_poll,
      backend_opts: [interval: 1000],
      dirs: ["lib/jarvis_web", "priv/static"]
  end

  config :jarvis, JarvisWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/jarvis_web/router\.ex$"E,
        ~r"lib/jarvis_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # A local, single-user tool: loopback only, plain http, no environment needed.
  # The secret key base is generated once into the Data directory
  # (JarvisWeb.Endpoint.init/2).
  config :jarvis, JarvisWeb.Endpoint,
    url: [host: "localhost"],
    check_origin: ["//localhost", "//127.0.0.1"],
    http: [ip: {127, 0, 0, 1}, port: port]
end
