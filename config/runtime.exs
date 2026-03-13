import Config

config :trpg_master,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  data_dir: System.get_env("DATA_DIR", "data"),
  ai_model: System.get_env("AI_MODEL", "claude-sonnet-4-20250514")

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :trpg_master, TrpgMasterWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  config :trpg_master, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
end
