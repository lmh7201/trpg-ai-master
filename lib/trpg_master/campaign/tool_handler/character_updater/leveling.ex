defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling do
  @moduledoc false

  alias TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling.{Choices, Progression}
  alias TrpgMaster.Rules.CharacterData

  require Logger

  def level_up_character(char, input) do
    current_level = char["level"] || 1
    target_level = target_level(char, current_level)

    if target_level > current_level do
      Logger.info("레벨업 적용: #{input["character_name"]} #{current_level} → #{target_level}")

      char
      |> Progression.apply_level_up(current_level, target_level)
      |> Choices.apply(input)
      |> Choices.mark_pending(target_level, char["class_id"], input)
    else
      Logger.info("레벨업 조건 미충족 또는 최대 레벨: #{input["character_name"]} (현재 레벨: #{current_level})")

      char
    end
  end

  def apply_xp_gain(char, xp_gained) do
    current_xp = char["xp"] || 0
    current_level = char["level"] || 1
    new_xp = current_xp + xp_gained
    new_level = min(CharacterData.level_for_xp(new_xp), 20)

    char = Map.put(char, "xp", new_xp)
    Logger.info("XP 획득: #{char["name"]} #{current_xp} → #{new_xp} XP")

    if new_level > current_level do
      Logger.info("레벨업 발생: #{char["name"]} #{current_level} → #{new_level}")

      char
      |> Progression.apply_level_up(current_level, new_level)
      |> Choices.mark_pending(new_level, char["class_id"], %{})
    else
      char
    end
  end

  defdelegate apply_level_up(char, old_level, new_level), to: Progression
  defdelegate maybe_apply_level_up_stats(new_char, old_char, changes), to: Progression

  defp target_level(char, current_level) do
    current_xp = char["xp"] || 0
    xp_based_level = min(CharacterData.level_for_xp(current_xp), 20)

    if xp_based_level > current_level, do: xp_based_level, else: min(current_level + 1, 20)
  end
end
