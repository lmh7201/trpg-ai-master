import Config

config :trpg_master, TrpgMasterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_must_be_at_least_64_bytes_long_so_here_is_some_padding_123456",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
