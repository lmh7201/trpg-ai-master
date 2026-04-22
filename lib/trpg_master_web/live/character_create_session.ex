defmodule TrpgMasterWeb.CharacterCreateSession do
  @moduledoc false

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreateFlow
  require Logger

  def mount_assigns(campaign_id, opts \\ []) do
    ensure_campaign_started(campaign_id, opts)

    classes = Keyword.get(opts, :classes, CharacterData.classes())

    if classes == [] do
      Logger.warning("CharacterCreateLive: 캐릭터 데이터 없음 → AI 캐릭터 생성으로 이동")
      {:navigate, "/play/#{campaign_id}"}
    else
      races = Keyword.get(opts, :races, CharacterData.races())
      backgrounds = Keyword.get(opts, :backgrounds, CharacterData.backgrounds())

      {:ok, CharacterCreateFlow.mount_assigns(campaign_id, classes, races, backgrounds)}
    end
  end

  def select_class(class_id, opts \\ []),
    do:
      select_entity(class_id, opts,
        opts_key: :get_class,
        default_getter: &CharacterData.get_class/1,
        applier: &CharacterCreateFlow.select_class/1
      )

  def select_race(race_id, opts \\ []),
    do:
      select_entity(race_id, opts,
        opts_key: :get_race,
        default_getter: &CharacterData.get_race/1,
        applier: &CharacterCreateFlow.select_race/1
      )

  def select_background(background_id, opts \\ []),
    do:
      select_entity(background_id, opts,
        opts_key: :get_background,
        default_getter: &CharacterData.get_background/1,
        applier: &CharacterCreateFlow.select_background/1
      )

  # id → (opts[opts_key] || default_getter).(id) → applier.(entity)
  defp select_entity(id, opts, cfg) do
    getter = Keyword.get(opts, cfg[:opts_key], cfg[:default_getter])
    id |> getter.() |> cfg[:applier].()
  end

  def finish(assigns, opts \\ []) do
    finish_flow = Keyword.get(opts, :finish_flow, &CharacterCreateFlow.finish/1)
    set_character = Keyword.get(opts, :set_character, &Server.set_character/2)

    case finish_flow.(assigns) do
      {:ok, character} ->
        campaign_id = assigns.campaign_id
        set_character.(campaign_id, character)
        {:ok, campaign_id}

      {:error, message} ->
        {:error, message}
    end
  end

  defp ensure_campaign_started(campaign_id, opts) do
    server_alive? = Keyword.get(opts, :server_alive?, &Server.alive?/1)
    start_campaign = Keyword.get(opts, :start_campaign, &Manager.start_campaign/1)

    unless server_alive?.(campaign_id) do
      case start_campaign.(campaign_id) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
