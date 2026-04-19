defmodule TrpgMasterWeb.CampaignSession do
  @moduledoc false

  alias TrpgMaster.Campaign.Server
  alias TrpgMasterWeb.{CampaignFlow, CampaignPresenter}

  def mount_assigns(campaign_id, opts \\ []) do
    start_campaign = Keyword.get(opts, :start_campaign)
    get_state = Keyword.get(opts, :get_state, &Server.get_state/1)

    case start_campaign_result(campaign_id, start_campaign) do
      {:ok, _} ->
        state = get_state.(campaign_id)
        {:ok, CampaignPresenter.mount_assigns(campaign_id, state)}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def call_ai(assigns, message, opts \\ []) do
    campaign_id = assigns.campaign_id
    player_action = Keyword.get(opts, :player_action, &Server.player_action/2)
    get_state = Keyword.get(opts, :get_state, &Server.get_state/1)

    case player_action.(campaign_id, message) do
      {:ok, [player_result | enemy_results]} when enemy_results != [] ->
        state = get_state.(campaign_id)
        CampaignFlow.apply_player_action_result(assigns, [player_result | enemy_results], state)

      {:ok, result} when not is_list(result) ->
        state = get_state.(campaign_id)
        CampaignFlow.apply_player_action_result(assigns, result, state)

      {:error, reason} ->
        {:error, CampaignFlow.apply_player_action_error(reason)}
    end
  end

  def display_enemy_turn(assigns, result, rest, opts \\ []) do
    campaign_id = assigns.campaign_id
    get_state = Keyword.get(opts, :get_state, &Server.get_state/1)
    state = get_state.(campaign_id)
    CampaignFlow.apply_enemy_turn(assigns, result, rest, state)
  end

  def end_session(assigns, opts \\ []) do
    campaign_id = assigns.campaign_id
    end_session = Keyword.get(opts, :end_session, &Server.end_session/1)
    result = end_session.(campaign_id)
    CampaignFlow.apply_end_session_result(assigns, result)
  end

  defp start_campaign_result(campaign_id, nil) do
    TrpgMaster.Campaign.Manager.start_campaign(campaign_id)
  end

  defp start_campaign_result(campaign_id, start_campaign_fun) do
    start_campaign_fun.(campaign_id)
  end
end
