defmodule TrpgMasterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :trpg_master

  @session_options [
    store: :cookie,
    key: "_trpg_master_key",
    signing_salt: "trpg_signing",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :trpg_master,
    gzip: false,
    only: TrpgMasterWeb.static_paths()

  # Serve Phoenix JS from deps
  plug Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    gzip: false

  # Serve LiveView JS from deps
  plug Plug.Static,
    at: "/assets/phoenix_live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug TrpgMasterWeb.Router
end
