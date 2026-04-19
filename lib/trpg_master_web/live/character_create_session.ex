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

  def select_class(class_id, opts \\ []) do
    get_class = Keyword.get(opts, :get_class, &CharacterData.get_class/1)
    class_id |> get_class.() |> CharacterCreateFlow.select_class()
  end

  def select_race(race_id, opts \\ []) do
    get_race = Keyword.get(opts, :get_race, &CharacterData.get_race/1)
    race_id |> get_race.() |> CharacterCreateFlow.select_race()
  end

  def select_background(background_id, opts \\ []) do
    get_background = Keyword.get(opts, :get_background, &CharacterData.get_background/1)
    background_id |> get_background.() |> CharacterCreateFlow.select_background()
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
