defmodule TrpgMasterWeb.CampaignPresenter.State do
  @moduledoc false

  alias TrpgMaster.AI.Models
  alias TrpgMasterWeb.CampaignPresenter.Messages

  def mount_assigns(campaign_id, state) do
    %{
      campaign_id: campaign_id,
      campaign_name: state.name,
      messages: Messages.display_messages(state.exploration_history ++ state.combat_history),
      input_text: "",
      loading: false,
      error: nil,
      last_player_message: nil,
      processing: false,
      ending_session: false,
      ai_model: state.ai_model || Models.default_model(),
      show_model_selector: false,
      available_models: Models.list_with_status()
    }
    |> Map.merge(state_assigns(state))
  end

  def state_assigns(state) do
    player_chars = player_characters(state.characters, state.combat_state)

    %{
      current_location: state.current_location,
      phase: state.phase,
      character: List.first(player_chars),
      characters: player_chars,
      combat_state: state.combat_state,
      mode: state.mode
    }
  end

  defp player_characters(characters, combat_state) do
    case get_in(combat_state, ["player_names"]) do
      names when is_list(names) and names != [] ->
        Enum.filter(characters, fn character -> character["name"] in names end)

      _ ->
        characters
    end
  end
end
