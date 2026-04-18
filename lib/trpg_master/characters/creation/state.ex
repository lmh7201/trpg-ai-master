defmodule TrpgMaster.Characters.Creation.State do
  @moduledoc false

  alias TrpgMaster.Characters.Creation.Definitions

  def initial_state(classes, races, backgrounds) do
    %{
      step: 1,
      steps: Definitions.steps(),
      ability_keys: Definitions.ability_keys(),
      ability_names: Definitions.ability_names(),
      classes: classes,
      races: races,
      backgrounds: backgrounds,
      selected_class: nil,
      selected_race: nil,
      selected_background: nil,
      class_skills: [],
      available_class_skills: [],
      class_skill_count: 0,
      bg_ability_2: nil,
      bg_ability_1: [],
      bg_abilities: [],
      ability_method: "standard_array",
      abilities: blank_abilities(),
      available_scores: Definitions.standard_array(),
      rolled_scores: nil,
      class_equip_choice: "A",
      bg_equip_choice: "A",
      is_spellcaster: false,
      cantrip_limit: 0,
      spell_limit: 0,
      selected_cantrips: [],
      selected_spells: [],
      available_cantrips: [],
      available_spells: [],
      character_name: "",
      alignment: "중립",
      appearance: "",
      backstory: "",
      error: nil,
      detail_panel: nil
    }
  end

  def class_selection(class) do
    class_id = class["id"]

    skill_opts =
      get_in(class, ["skillProficiencies", "options", "ko"]) ||
        get_in(class, ["skillProficiencies", "options", "en"]) || []

    skill_count = get_in(class, ["skillProficiencies", "choose"]) || 2
    spell_info = Definitions.spellcasting_info(class_id)

    %{
      selected_class: class,
      available_class_skills: skill_opts,
      class_skill_count: skill_count,
      class_skills: [],
      is_spellcaster: Definitions.spellcasting_class?(class_id),
      cantrip_limit: Map.get(spell_info, :cantrips, 0),
      spell_limit: Map.get(spell_info, :spells, 0),
      selected_cantrips: [],
      selected_spells: [],
      detail_panel: nil
    }
  end

  def background_selection(background) do
    bg_abilities =
      case get_in(background, ["abilityScores", "en"]) do
        list when is_list(list) ->
          Enum.map(list, &ability_en_to_key/1)

        _ ->
          []
      end

    %{
      selected_background: background,
      bg_abilities: bg_abilities,
      bg_ability_2: nil,
      bg_ability_1: [],
      detail_panel: nil
    }
  end

  def ability_method_updates(method) do
    %{
      ability_method: method,
      abilities: blank_abilities(),
      available_scores:
        if(method == "standard_array", do: Definitions.standard_array(), else: []),
      rolled_scores: nil
    }
  end

  def assign_ability(assigns, key, value) do
    abilities = Map.get(assigns, :abilities, %{})

    old_key =
      Enum.find(Definitions.ability_keys(), fn ability_key ->
        abilities[ability_key] == value && ability_key != key
      end)

    abilities =
      if old_key do
        Map.put(abilities, old_key, nil)
      else
        abilities
      end

    abilities = Map.put(abilities, key, value)

    %{
      abilities: abilities,
      available_scores: available_scores(assigns.ability_method, assigns.rolled_scores, abilities)
    }
  end

  def clear_ability(assigns, key) do
    abilities = Map.put(assigns.abilities, key, nil)

    %{
      abilities: abilities,
      available_scores: available_scores(assigns.ability_method, assigns.rolled_scores, abilities)
    }
  end

  def roll_abilities do
    scores =
      for _ <- 1..6 do
        rolls = for _ <- 1..4, do: Enum.random(1..6)
        rolls |> Enum.sort(:desc) |> Enum.take(3) |> Enum.sum()
      end
      |> Enum.sort(:desc)

    %{
      rolled_scores: scores,
      available_scores: scores,
      abilities: blank_abilities()
    }
  end

  defp blank_abilities do
    Map.new(Definitions.ability_keys(), &{&1, nil})
  end

  defp available_scores("standard_array", _rolled_scores, abilities) do
    remaining_scores(Definitions.standard_array(), abilities)
  end

  defp available_scores("roll", rolled_scores, abilities) do
    remaining_scores(rolled_scores || [], abilities)
  end

  defp available_scores(_, _rolled_scores, _abilities), do: []

  defp remaining_scores(all_scores, abilities) do
    used = abilities |> Map.values() |> Enum.reject(&is_nil/1)

    Enum.reduce(used, all_scores, fn value, acc ->
      case Enum.find_index(acc, &(&1 == value)) do
        nil -> acc
        idx -> List.delete_at(acc, idx)
      end
    end)
  end

  defp ability_en_to_key(name) do
    case String.downcase(to_string(name)) do
      "strength" -> "str"
      "dexterity" -> "dex"
      "constitution" -> "con"
      "intelligence" -> "int"
      "wisdom" -> "wis"
      "charisma" -> "cha"
      other -> other
    end
  end
end
