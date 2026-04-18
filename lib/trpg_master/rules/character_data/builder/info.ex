defmodule TrpgMaster.Rules.CharacterData.Builder.Info do
  @moduledoc false

  def get_character_info(character, category) do
    case category do
      "full" ->
        character

      "abilities" ->
        Map.take(character, [
          "abilities",
          "ability_modifiers",
          "saving_throws",
          "skill_proficiencies",
          "proficiency_bonus"
        ])

      "combat" ->
        Map.take(character, [
          "hp_max",
          "hp_current",
          "ac",
          "speed",
          "hit_die",
          "weapon_proficiencies",
          "armor_training",
          "conditions",
          "abilities",
          "ability_modifiers",
          "proficiency_bonus"
        ])

      "spells" ->
        Map.take(character, [
          "spells_known",
          "spell_slots",
          "spell_slots_used",
          "abilities",
          "ability_modifiers",
          "proficiency_bonus",
          "level",
          "class_id"
        ])

      "equipment" ->
        Map.take(character, ["equipment", "inventory"])

      "features" ->
        Map.take(character, [
          "features",
          "background_feat",
          "class_features",
          "class",
          "race",
          "background",
          "level"
        ])

      "proficiencies" ->
        Map.take(character, [
          "saving_throws",
          "skill_proficiencies",
          "weapon_proficiencies",
          "armor_training",
          "tool_proficiencies",
          "proficiency_bonus"
        ])

      "summary" ->
        Map.take(character, [
          "name",
          "class",
          "race",
          "background",
          "alignment",
          "level",
          "hp_max",
          "hp_current",
          "ac",
          "speed"
        ])

      _ ->
        %{"error" => "알 수 없는 카테고리: #{category}"}
    end
  end
end
