defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater do
  @moduledoc false

  alias TrpgMaster.Campaign.ToolHandler.CharacterUpdater.{Changes, Leveling}

  require Logger

  def update_character(state, input) do
    char_name = input["character_name"]
    changes = input["changes"] || %{}

    Logger.info("캐릭터 업데이트: #{char_name} — #{inspect(changes)}")

    characters =
      case Changes.find_character_index(state.characters, char_name) do
        nil ->
          Logger.warning("update_character: '#{char_name}' 캐릭터 없음 — 무시 (위자드로만 캐릭터 생성 가능)")
          state.characters

        idx ->
          List.update_at(state.characters, idx, fn char ->
            char
            |> Changes.apply_character_changes(changes)
            |> Leveling.maybe_apply_level_up_stats(char, changes)
          end)
      end

    state = %{state | characters: characters}
    Changes.sync_enemy_hp_to_combat_state(state, char_name, changes)
  end

  def level_up(state, input) do
    char_name = input["character_name"]
    Logger.info("레벨업 요청: #{char_name}")

    characters =
      case Changes.find_character_index(state.characters, char_name) do
        nil ->
          Logger.warning("레벨업 대상 캐릭터 없음: #{char_name}")
          state.characters

        idx ->
          List.update_at(state.characters, idx, &Leveling.level_up_character(&1, input))
      end

    %{state | characters: characters}
  end

  defdelegate apply_xp_gain(char, xp_gained), to: Leveling
  defdelegate apply_level_up(char, old_level, new_level), to: Leveling
end
