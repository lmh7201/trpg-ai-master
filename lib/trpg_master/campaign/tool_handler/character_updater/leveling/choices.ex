defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling.Choices do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  require Logger

  def apply(char, input) do
    char
    |> apply_asi(input["asi"])
    |> apply_feat(input["feat"])
    |> apply_subclass(input["subclass"])
    |> apply_new_spells(input["new_spells"])
  end

  def mark_pending(char, target_level, class_id, input) do
    char
    |> maybe_mark_asi_pending(target_level, class_id, input["asi"], input["feat"])
    |> maybe_mark_subclass_pending(target_level, class_id, input["subclass"])
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
    resolved_name = resolve_feat_name(feat_name)
    existing = char["feats"] || []

    if resolved_name in existing do
      char
    else
      Map.put(char, "feats", existing ++ [resolved_name])
    end
  end

  defp apply_feat(char, _), do: char

  defp resolve_feat_name(feat_name) do
    name_lower = String.downcase(feat_name)

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
  end

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
      known_spells = Map.get(acc, "spells_known", %{})

      updated_known_spells =
        Map.update(known_spells, spell_level_key(spell), [spell_name], fn existing ->
          if spell_name in existing, do: existing, else: existing ++ [spell_name]
        end)

      Map.put(acc, "spells_known", updated_known_spells)
    end)
  end

  defp apply_new_spells(char, _), do: char

  defp spell_level_key(%{"level" => 0}), do: "cantrips"

  defp spell_level_key(%{"level" => level}) when is_integer(level) and level >= 1,
    do: Integer.to_string(level)

  defp spell_level_key(_spell), do: "1"
end
