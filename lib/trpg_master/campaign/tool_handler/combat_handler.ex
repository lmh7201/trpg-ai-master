defmodule TrpgMaster.Campaign.ToolHandler.CombatHandler do
  @moduledoc """
  `start_combat`, `end_combat` 도구 결과를 state에 반영한다.
  """

  alias TrpgMaster.Campaign.ToolHandler.CharacterUpdater
  require Logger

  @doc """
  전투 시작: 참가자/적 정보를 `state.combat_state`에 담고 phase를 `:combat`으로 전환.
  """
  def start(state, input) when is_map(input) do
    if state.combat_state do
      Logger.warning(
        "[Campaign #{state.id}] 기존 전투가 진행 중인데 새 전투가 시작됨. 기존 전투를 덮어씁니다."
      )
    end

    participants = input["participants"] || []
    enemies = input["enemies"]
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    player_names = Enum.map(state.characters, fn c -> c["name"] end)

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => [],
      "player_names" => player_names
    }

    combat =
      if is_list(enemies) && enemies != [] do
        Map.put(combat, "enemies", enemies)
      else
        combat
      end

    %{state | phase: :combat, combat_state: combat}
  end

  @doc """
  전투 종료: 플레이어 캐릭터만 남기고, XP 지급 시 레벨업까지 재계산한다.
  """
  def finish(state, input) when is_map(input) do
    Logger.info("전투 종료")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    xp_gained = input["xp"] || 0

    characters =
      if xp_gained > 0 do
        Enum.map(characters, fn char -> CharacterUpdater.apply_xp_gain(char, xp_gained) end)
      else
        characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end
end
