defmodule TrpgMasterWeb.Router do
  use TrpgMasterWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TrpgMasterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :require_auth do
    plug :check_session_auth
  end

  # 인증 불필요 (로그인 페이지)
  scope "/", TrpgMasterWeb do
    pipe_through :browser

    get "/login", LoginController, :show
    post "/login", LoginController, :login
    delete "/logout", LoginController, :logout
  end

  # 인증 필요
  scope "/", TrpgMasterWeb do
    pipe_through [:browser, :require_auth]

    live "/", LobbyLive, :index
    live "/play/:id", CampaignLive, :play
    live "/history/:id", HistoryLive, :history
  end

  # ── Auth Plug ──────────────────────────────────────────────────────────────

  defp check_session_auth(conn, _opts) do
    password = Application.get_env(:trpg_master, :auth_password)

    # AUTH_PASSWORD 미설정 시 인증 건너뜀 (로컬 개발 편의)
    if is_nil(password) || password == "" do
      conn
    else
      if get_session(conn, :authenticated) do
        conn
      else
        conn
        |> Phoenix.Controller.redirect(to: "/login")
        |> halt()
      end
    end
  end
end
