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

  scope "/", TrpgMasterWeb do
    pipe_through :browser

    live "/", LobbyLive, :index
    live "/play/:id", CampaignLive, :play
  end
end
