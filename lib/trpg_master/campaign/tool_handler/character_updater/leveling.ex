defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  require Logger

  def level_up_character(char, input) do
    current_level = char["level"] || 1
    current_xp = char["xp"] || 0
    xp_based_level = min(CharacterData.level_for_xp(current_xp), 20)

    target_level =
      if xp_based_level > current_level, do: xp_based_level, else: current_level + 1

    target_level = min(target_level, 20)

    if target_level > current_level do
      Logger.info("레벨업 적용: #{input["character_name"]} #{current_level} → #{target_level}")

      char
      |> apply_level_up(current_level, target_level)
      |> apply_asi(input["asi"])
      |> apply_feat(input["feat"])
      |> apply_subclass(input["subclass"])
      |> apply_new_spells(input["new_spells"])
      |> maybe_mark_asi_pending(target_level, char["class_id"], input["asi"], input["feat"])
      |> maybe_mark_subclass_pending(target_level, char["class_id"], input["subclass"])
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
      |> apply_level_up(current_level, new_level)
      |> maybe_mark_asi_pending(new_level, char["class_id"], nil, nil)
      |> maybe_mark_subclass_pending(new_level, char["class_id"], nil)
    else
      char
    end
  end

  def apply_level_up(char, old_level, new_level) do
    con_mod = get_in(char, ["ability_modifiers", "con"]) || 0
    hit_die = CharacterData.parse_hit_die(char["hit_die"])

    levels_gained = new_level - old_level
    hp_per_level = max(div(hit_die, 2) + 1 + con_mod, 1)
    hp_increase = hp_per_level * levels_gained

    new_hp_max = (char["hp_max"] || 1) + hp_increase
    new_prof_bonus = CharacterData.proficiency_bonus_for_level(new_level)

    class_id = char["class_id"]
    new_spell_slots = CharacterData.spell_slots_for_class_level(class_id, new_level)
    new_cantrips_count = CharacterData.cantrips_known_for_class_level(class_id, new_level)
    new_spells_count = CharacterData.spells_known_for_class_level(class_id, new_level)

    new_class_features =
      CharacterData.class_features_for_levels(class_id, old_level + 1, new_level)

    existing_class_features = char["class_features"] || []
    merged_class_features = existing_class_features ++ new_class_features

    subclass_id = char["subclass_id"]

    new_subclass_features =
      if subclass_id do
        CharacterData.subclass_features_for_levels(subclass_id, old_level + 1, new_level)
      else
        []
      end

    existing_subclass_features = char["subclass_features"] || []
    merged_subclass_features = existing_subclass_features ++ new_subclass_features

    char
    |> Map.put("level", new_level)
    |> Map.put("hp_max", new_hp_max)
    |> Map.put("hp_current", (char["hp_current"] || 1) + hp_increase)
    |> Map.put("proficiency_bonus", new_prof_bonus)
    |> Map.put("class_features", merged_class_features)
    |> Map.put("subclass_features", merged_subclass_features)
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

  defp maybe_mark_asi_pending(char, target_level, class_id, asi, feat) do
    if CharacterData.asi_level?(target_level, class_id) && is_nil(asi) && is_nil(feat) do
      Map.put(char, "asi_pending", true)
    else
      Map.delete(char, "asi_pending")
    end
  end

  defp maybe_mark_subclass_pending(char, target_level, class_id, subclass) do
    if CharacterData.subclass_level?(target_level, class_id) &&
         is_nil(subclass) &&
         is_nil(char["subclass"]) do
      Map.put(char, "subclass_pending", true)
    else
      Map.delete(char, "subclass_pending")
    end
  end

  defp apply_asi(char, asi) when is_map(asi) do
    abilities = char["abilities"] || %{}

    new_abilities =
      Enum.reduce(asi, abilities, fn {stat, amount}, acc ->
        current = acc[stat] || 10
        Map.put(acc, stat, min(current + amount, 20))
      end)

    new_modifiers =
      Map.new(new_abilities, fn {key, value} ->
        {key, CharacterData.ability_modifier(value)}
      end)

    char
    |> Map.put("abilities", new_abilities)
    |> Map.put("ability_modifiers", new_modifiers)
  end

  defp apply_asi(char, _), do: char

  defp apply_feat(char, feat_name) when is_binary(feat_name) and feat_name != "" do
    name_lower = String.downcase(feat_name)

    resolved_name =
      CharacterData.feats()
      |> Enum.find(fn feat ->
        ko = get_in(feat, ["name", "ko"]) || ""
        en = get_in(feat, ["name", "en"]) || ""
        String.downcase(ko) == name_lower || String.downcase(en) == name_lower
      end)
      |> case do
        nil -> feat_name
        feat -> get_in(feat, ["name", "ko"]) || get_in(feat, ["name", "en"]) || feat_name
      end

    existing = char["feats"] || []

    if resolved_name in existing do
      char
    else
      Map.put(char, "feats", existing ++ [resolved_name])
    end
  end

  defp apply_feat(char, _), do: char

  defp apply_subclass(char, subclass_name)
       when is_binary(subclass_name) and subclass_name != "" do
    class_id = char["class_id"]
    resolved = CharacterData.resolve_subclass_name(class_id, subclass_name)
    subclass_id = CharacterData.resolve_subclass_id(class_id, subclass_name)

    Logger.info("서브클래스 선택: #{char["name"]} → #{resolved} (id: #{subclass_id})")

    char = Map.put(char, "subclass", resolved)
    char = if subclass_id, do: Map.put(char, "subclass_id", subclass_id), else: char

    if subclass_id do
      selection_level = char["level"] || 1

      new_features =
        CharacterData.subclass_features_for_level(subclass_id, selection_level)
        |> Enum.map(fn name -> %{"name" => name, "level" => selection_level} end)

      existing = char["subclass_features"] || []
      Map.put(char, "subclass_features", existing ++ new_features)
    else
      char
    end
  end

  defp apply_subclass(char, _), do: char

  defp apply_new_spells(char, nil), do: char
  defp apply_new_spells(char, []), do: char

  defp apply_new_spells(char, new_spells) when is_list(new_spells) do
    Enum.reduce(new_spells, char, fn spell, acc ->
      spell_name = spell["name"] || inspect(spell)

      level_key =
        case spell["level"] do
          0 -> "cantrips"
          level when is_integer(level) and level >= 1 -> Integer.to_string(level)
          _ -> "1"
        end

      known_spells = Map.get(acc, "spells_known", %{})

      updated_known_spells =
        Map.update(known_spells, level_key, [spell_name], fn existing ->
          if spell_name in existing, do: existing, else: existing ++ [spell_name]
        end)

      Map.put(acc, "spells_known", updated_known_spells)
    end)
  end

  defp apply_new_spells(char, _), do: char

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
