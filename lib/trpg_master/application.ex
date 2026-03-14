defmodule TrpgMaster.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TrpgMasterWeb.Telemetry,
      {Phoenix.PubSub, name: TrpgMaster.PubSub},
      {DNSCluster, query: Application.get_env(:trpg_master, :dns_cluster_query) || :ignore},
      TrpgMaster.Rules.Loader,
      TrpgMaster.Oracle.Loader,
      {Registry, keys: :unique, name: TrpgMaster.Campaign.Registry},
      {DynamicSupervisor, name: TrpgMaster.Campaign.Manager, strategy: :one_for_one},
      TrpgMasterWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TrpgMaster.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    TrpgMasterWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
