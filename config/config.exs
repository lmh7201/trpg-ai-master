import Config

config :trpg_master,
  generators: [timestamp_type: :utc_datetime]

config :trpg_master, TrpgMasterWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TrpgMasterWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: TrpgMaster.PubSub,
  live_view: [signing_salt: "trpg_salt"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
