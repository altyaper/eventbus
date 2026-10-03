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
#     PHX_SERVER=true bin/eventbus start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :eventbus, EventbusWeb.Endpoint, server: true
end

# Key that proves ownership at the first-run /setup screen. Optional: when
# unset, a key is generated on first boot and stored in the database (see
# Eventbus.Settings). Publishing uses per-application credentials.
api_key = System.get_env("EVENTBUS_API_KEY", "")

if api_key != "" do
  config :eventbus, :api_key, api_key
end

config :eventbus, EventbusWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :eventbus, EventbusWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/eventbus_web/router\.ex$",
        ~r"lib/eventbus_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # Either DATABASE_URL, or discrete DATABASE_HOST/POSTGRES_* vars (what
  # docker-compose.yml passes). The discrete form never goes through URL
  # parsing, so passwords with `/`, `+`, `@` etc. (e.g. base64 from
  # `openssl rand -base64`) work without percent-encoding.
  connection =
    case System.get_env("DATABASE_URL") do
      url when url not in [nil, ""] ->
        [url: url]

      _ ->
        [
          hostname:
            System.get_env("DATABASE_HOST") ||
              raise("""
              environment variable DATABASE_URL or DATABASE_HOST is missing.
              Set DATABASE_URL (ecto://USER:PASS@HOST/DATABASE) or
              DATABASE_HOST plus POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB.
              """),
          username: System.fetch_env!("POSTGRES_USER"),
          password: System.fetch_env!("POSTGRES_PASSWORD"),
          database: System.fetch_env!("POSTGRES_DB")
        ]
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :eventbus, Eventbus.Repo, connection

  config :eventbus, Eventbus.Repo,
    # ssl: true,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base = System.get_env("SECRET_KEY_BASE", "")

  # Checked here rather than left to Plug, which only raises on the first
  # request that sets a cookie, long after the app looks healthy.
  if byte_size(secret_key_base) < 64 do
    raise """
    environment variable SECRET_KEY_BASE is missing or shorter than 64 bytes.
    Generate one with: openssl rand -base64 64 | tr -d '\\n'  (or mix phx.gen.secret)
    """
  end

  host = System.get_env("PHX_HOST") || "example.com"

  config :eventbus, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Origins always allowed to open the LiveView/Channels websockets: PHX_HOST
  # plus any in PHX_EXTRA_ORIGINS (comma-separated), e.g. a public domain
  # behind a reverse proxy alongside the Pi's LAN IP. The superadmin can allow
  # more at /settings; see Eventbus.Origins for the pattern format.
  extra_origins =
    System.get_env("PHX_EXTRA_ORIGINS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))

  config :eventbus, :env_origins, [host | extra_origins]

  config :eventbus, EventbusWeb.Endpoint,
    url: [host: host, port: String.to_integer(System.get_env("PORT", "4000")), scheme: "http"],
    check_origin: {Eventbus.Origins, :allowed?, []},
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :eventbus, EventbusWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :eventbus, EventbusWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :eventbus, Eventbus.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
