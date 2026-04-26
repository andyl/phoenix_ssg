import Config

config :phoenix_ssg, PhoenixSsg.TestSupport.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 0],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  render_errors: [formats: [], layout: false]

config :logger, level: :warning

config :phoenix, :json_library, Jason
