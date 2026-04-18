defmodule TrpgMaster.Rules.CharacterData.Builder.Creation do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData
  alias TrpgMaster.Rules.CharacterData.Progression

  def build_character_map(params) do
    class_data = CharacterData.get_class(params.class_id)
    race_data = CharacterData.get_race(params.race_id)
    background_data = CharacterData.get_background(params.background_id)

    class_name =
      get_in(class_data, ["name", "ko"]) ||
        get_in(class_data, ["name", "en"]) || params.class_id

    race_name = extract_race_name(race_data)

    background_name =
      get_in(background_data, ["name", "ko"]) ||
        get_in(background_data, ["name", "en"]) || params.background_id

    hit_die = Progression.parse_hit_die(class_data["hitPointDie"])
    con_mod = Progression.ability_modifier(params.abilities["con"] || 10)
    hp_max = hit_die + con_mod
    ac = calculate_ac(params)
    skill_profs = (params[:class_skills] || []) ++ extract_background_skills(background_data)
    spell_slots = Progression.spell_slots_for_class_level(params.class_id, 1) || %{}

    %{
      "name" => params.name,
      "class" => class_name,
      "class_id" => params.class_id,
      "subclass" => nil,
      "race" => race_name,
      "race_id" => params.race_id,
      "background" => background_name,
      "background_id" => params.background_id,
      "level" => 1,
      "xp" => 0,
      "hp_max" => hp_max,
      "hp_current" => hp_max,
      "hit_die" => class_data["hitPointDie"],
      "ac" => ac,
      "speed" => extract_speed(race_data),
      "proficiency_bonus" => 2,
      "abilities" => params.abilities,
      "ability_modifiers" => calculate_all_modifiers(params.abilities),
      "saving_throws" => class_data["savingThrowProficiencies"],
      "skill_proficiencies" => skill_profs,
      "weapon_proficiencies" => class_data["weaponProficiencies"],
      "armor_training" => class_data["armorTraining"],
      "tool_proficiencies" => extract_tool_prof(background_data),
      "features" => extract_level1_features(class_data, race_data),
      "background_feat" => extract_background_feat(background_data),
      "equipment" => params[:equipment] || [],
      "inventory" => params[:equipment] || [],
      "spells_known" => params[:spells] || %{},
      "conditions" => [],
      "spell_slots" => spell_slots,
      "spell_slots_used" => %{},
      "feats" => [],
      "class_features" => Progression.class_features_for_levels(params.class_id, 1, 1),
      "alignment" => Map.get(params, :alignment, "중립"),
      "appearance" => Map.get(params, :appearance, ""),
      "backstory" => Map.get(params, :backstory, "")
    }
  end

  defp extract_race_name(nil), do: "알 수 없음"
  defp extract_race_name(%{"name" => %{"ko" => ko}}), do: ko
  defp extract_race_name(%{"name" => name}) when is_binary(name), do: name
  defp extract_race_name(_), do: "알 수 없음"

  defp extract_speed(nil), do: 30
  defp extract_speed(%{"basicTraits" => %{"speed" => %{"value" => value}}}), do: value
  defp extract_speed(_), do: 30

  defp extract_background_skills(nil), do: []
  defp extract_background_skills(%{"skillProficiencies" => %{"ko" => skills}}), do: skills
  defp extract_background_skills(%{"skillProficiencies" => %{"en" => skills}}), do: skills
  defp extract_background_skills(_), do: []

  defp extract_tool_prof(nil), do: []
  defp extract_tool_prof(%{"toolProficiency" => %{"ko" => tool}}), do: [tool]
  defp extract_tool_prof(%{"toolProficiency" => %{"en" => tool}}), do: [tool]
  defp extract_tool_prof(_), do: []

  defp extract_background_feat(nil), do: nil
  defp extract_background_feat(%{"feat" => %{"name" => %{"ko" => name}}}), do: name
  defp extract_background_feat(%{"feat" => %{"name" => %{"en" => name}}}), do: name
  defp extract_background_feat(_), do: nil

  defp extract_level1_features(class_data, race_data) do
    class_features =
      case class_data["features"] do
        features when is_list(features) ->
          row = Enum.find(features, %{}, &(&1["level"] == 1))
          get_in(row, ["features", "ko"]) || get_in(row, ["features", "en"]) || []

        _ ->
          []
      end

    race_features =
      case race_data do
        %{"traits" => traits} when is_list(traits) ->
          Enum.map(traits, fn trait ->
            get_in(trait, ["name", "ko"]) || get_in(trait, ["name", "en"]) || "특성"
          end)

        _ ->
          []
      end

    class_features ++ race_features
  end

  defp calculate_all_modifiers(abilities) when is_map(abilities) do
    Map.new(abilities, fn {key, value} -> {key, Progression.ability_modifier(value)} end)
  end

  defp calculate_all_modifiers(_), do: %{}

  defp calculate_ac(params) do
    dex_mod = Progression.ability_modifier(params.abilities["dex"] || 10)

    case params[:armor_choice] do
      nil ->
        10 + dex_mod

      "none" ->
        10 + dex_mod

      armor_id ->
        armor_data = Enum.find(flat_armor_list(), &(&1["id"] == armor_id))
        if armor_data, do: compute_armor_ac(armor_data, dex_mod), else: 10 + dex_mod
    end
  end

  defp flat_armor_list do
    data = CharacterData.armor()

    cond do
      is_map(data) -> Map.get(data, "armor", []) ++ Map.get(data, "shields", [])
      is_list(data) -> data
      true -> []
    end
  end

  defp compute_armor_ac(%{"ac" => ac_str}, dex_mod) when is_binary(ac_str) do
    cond do
      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier\s*\(max\s*(\d+)\)/i, ac_str) ->
        [_, base_str, max_str] = match
        base = String.to_integer(base_str)
        max_dex = String.to_integer(max_str)
        base + min(dex_mod, max_dex)

      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier/i, ac_str) ->
        [_, base_str] = match
        String.to_integer(base_str) + dex_mod

      match = Regex.run(~r/^(\d+)$/, String.trim(ac_str)) ->
        [_, base_str] = match
        String.to_integer(base_str)

      true ->
        10 + dex_mod
    end
  end

  defp compute_armor_ac(%{"ac" => %{"en" => ac_str}}, dex_mod) when is_binary(ac_str) do
    compute_armor_ac(%{"ac" => ac_str}, dex_mod)
  end

  defp compute_armor_ac(%{"ac" => ac_info}, dex_mod) when is_map(ac_info) do
    base = Map.get(ac_info, "base", 10)
    add_dex = Map.get(ac_info, "addDex", true)
    max_dex = Map.get(ac_info, "maxDex")

    cond do
      not add_dex -> base
      max_dex -> base + min(dex_mod, max_dex)
      true -> base + dex_mod
    end
  end

  defp compute_armor_ac(%{"ac" => ac}, _dex_mod) when is_integer(ac), do: ac
  defp compute_armor_ac(_, dex_mod), do: 10 + dex_mod
end
