defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling.Progression do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  def apply_level_up(char, old_level, new_level) do
    hp_increase = hp_increase(char, old_level, new_level)
    class_id = char["class_id"]
    new_spell_slots = CharacterData.spell_slots_for_class_level(class_id, new_level)
    new_cantrips_count = CharacterData.cantrips_known_for_class_level(class_id, new_level)
    new_spells_count = CharacterData.spells_known_for_class_level(class_id, new_level)

    char
    |> Map.put("level", new_level)
    |> Map.put("hp_max", (char["hp_max"] || 1) + hp_increase)
    |> Map.put("hp_current", (char["hp_current"] || 1) + hp_increase)
    |> Map.put("proficiency_bonus", CharacterData.proficiency_bonus_for_level(new_level))
    |> Map.put("class_features", merge_class_features(char, class_id, old_level, new_level))
    |> Map.put("subclass_features", merge_subclass_features(char, old_level, new_level))
    |> maybe_put_spell_slots(new_spell_slots)
    |> maybe_put_known_spell_counts(new_cantrips_count, new_spells_count)
  end

  def maybe_apply_level_up_stats(new_char, old_char, changes) do
    old_level = old_char["level"] || 1
    new_level = new_char["level"] || 1

    if new_level > old_level && is_nil(changes["hp_max"]) do
      apply_level_up(new_char, old_level, new_level)
    else
      new_char
    end
  end

  defp hp_increase(char, old_level, new_level) do
    con_mod = get_in(char, ["ability_modifiers", "con"]) || 0
    hit_die = CharacterData.parse_hit_die(char["hit_die"])
    levels_gained = new_level - old_level
    hp_per_level = max(div(hit_die, 2) + 1 + con_mod, 1)

    hp_per_level * levels_gained
  end

  defp merge_class_features(char, class_id, old_level, new_level) do
    existing = char["class_features"] || []
    existing ++ CharacterData.class_features_for_levels(class_id, old_level + 1, new_level)
  end

  defp merge_subclass_features(char, old_level, new_level) do
    existing = char["subclass_features"] || []

    case char["subclass_id"] do
      nil ->
        existing

      subclass_id ->
        existing ++
          CharacterData.subclass_features_for_levels(subclass_id, old_level + 1, new_level)
    end
  end

  defp maybe_put_spell_slots(updated, nil), do: updated

  defp maybe_put_spell_slots(updated, new_spell_slots) do
    updated
    |> Map.put("spell_slots", new_spell_slots)
    |> Map.update("spell_slots_used", %{}, fn used ->
      Map.merge(
        used,
        Map.new(new_spell_slots, fn {level, _count} -> {level, Map.get(used, level, 0)} end)
      )
    end)
  end

  defp maybe_put_known_spell_counts(updated, new_cantrips_count, new_spells_count) do
    updated =
      if new_cantrips_count,
        do: Map.put(updated, "cantrips_known_count", new_cantrips_count),
        else: updated

    if new_spells_count,
      do: Map.put(updated, "spells_known_count", new_spells_count),
      else: updated
  end
end
