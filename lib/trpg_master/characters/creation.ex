defmodule TrpgMaster.Characters.Creation do
  @moduledoc """
  캐릭터 생성 위저드의 상태 계산, 검증, 최종 캐릭터 조립을 담당한다.
  """

  alias TrpgMaster.Rules.CharacterData

  @steps [
    {1, "클래스", "class"},
    {2, "종족", "race"},
    {3, "배경", "background"},
    {4, "능력치", "abilities"},
    {5, "장비", "equipment"},
    {6, "주문", "spells"},
    {7, "완성", "summary"}
  ]

  @standard_array [15, 14, 13, 12, 10, 8]

  @ability_keys ["str", "dex", "con", "int", "wis", "cha"]
  @ability_names %{
    "str" => "근력",
    "dex" => "민첩",
    "con" => "건강",
    "int" => "지능",
    "wis" => "지혜",
    "cha" => "매력"
  }

  @spellcasting_classes %{
    "bard" => %{cantrips: 2, spells: 4},
    "cleric" => %{cantrips: 3, spells: :wis_mod_plus_level},
    "druid" => %{cantrips: 2, spells: :wis_mod_plus_level},
    "ranger" => %{cantrips: 0, spells: 2},
    "sorcerer" => %{cantrips: 4, spells: 2},
    "warlock" => %{cantrips: 2, spells: 2},
    "wizard" => %{cantrips: 3, spells: 6}
  }

  def initial_state(classes, races, backgrounds) do
    %{
      step: 1,
      steps: @steps,
      ability_keys: @ability_keys,
      ability_names: @ability_names,
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
      available_scores: @standard_array,
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
    spell_info = Map.get(@spellcasting_classes, class_id, %{cantrips: 0, spells: 0})

    %{
      selected_class: class,
      available_class_skills: skill_opts,
      class_skill_count: skill_count,
      class_skills: [],
      is_spellcaster: Map.has_key?(@spellcasting_classes, class_id),
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
      available_scores: if(method == "standard_array", do: @standard_array, else: []),
      rolled_scores: nil
    }
  end

  def assign_ability(assigns, key, value) do
    abilities = assigns.abilities

    old_key =
      Enum.find(@ability_keys, fn ability_key ->
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

  def validate_step(%{step: 1} = assigns) do
    cond do
      is_nil(assigns.selected_class) ->
        {:error, "클래스를 선택하세요."}

      length(assigns.class_skills) < assigns.class_skill_count ->
        {:error, "기술 숙련 #{assigns.class_skill_count}개를 선택하세요."}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 2} = assigns) do
    if is_nil(assigns.selected_race), do: {:error, "종족을 선택하세요."}, else: :ok
  end

  def validate_step(%{step: 3} = assigns) do
    cond do
      is_nil(assigns.selected_background) ->
        {:error, "배경을 선택하세요."}

      is_nil(assigns.bg_ability_2) and assigns.bg_ability_1 == [] ->
        {:error, "능력치 보너스를 배정하세요. (+2 하나 또는 +1 둘)"}

      assigns.bg_ability_1 != [] and length(assigns.bg_ability_1) < 2 ->
        {:error, "+1을 하나 더 배정하세요. (총 2곳)"}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 4} = assigns) do
    all_assigned = Enum.all?(@ability_keys, fn key -> not is_nil(assigns.abilities[key]) end)

    cond do
      assigns.ability_method == "roll" and is_nil(assigns.rolled_scores) ->
        {:error, "주사위를 굴려주세요."}

      not all_assigned ->
        {:error, "모든 능력치에 값을 배정하세요."}

      true ->
        :ok
    end
  end

  def validate_step(%{step: 5}), do: :ok

  def validate_step(%{step: 6} = assigns) do
    if assigns.is_spellcaster do
      spell_limit = resolved_spell_limit(assigns)

      cond do
        length(assigns.selected_cantrips) < assigns.cantrip_limit and assigns.cantrip_limit > 0 ->
          {:error, "소마법 #{assigns.cantrip_limit}개를 선택하세요."}

        length(assigns.selected_spells) < spell_limit and spell_limit > 0 ->
          {:error, "1레벨 주문 #{spell_limit}개를 선택하세요."}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  def validate_step(%{step: 7} = assigns) do
    if assigns.character_name == "", do: {:error, "캐릭터 이름을 입력하세요."}, else: :ok
  end

  def validate_step(_), do: :ok

  def prepare_step(assigns, 6) do
    if assigns.is_spellcaster do
      class_id = assigns.selected_class["id"]
      class_en = get_in(assigns.selected_class, ["name", "en"]) || class_id

      cantrips = CharacterData.cantrips_for_class(class_en)
      spells = CharacterData.level1_spells_for_class(class_en)

      spell_limit =
        case @spellcasting_classes[class_id][:spells] do
          :wis_mod_plus_level ->
            wis = final_ability_score(assigns, "wis")
            max(1, CharacterData.ability_modifier(wis) + 1)

          :int_mod_plus_level ->
            int = final_ability_score(assigns, "int")
            max(1, CharacterData.ability_modifier(int) + 1)

          n when is_integer(n) ->
            n

          _ ->
            0
        end

      %{
        available_cantrips: cantrips,
        available_spells: spells,
        spell_limit: spell_limit,
        selected_cantrips: [],
        selected_spells: []
      }
    else
      %{}
    end
  end

  def prepare_step(_assigns, _step), do: %{}

  def build_character(assigns) do
    abilities = final_abilities_map(assigns)
    equipment = collect_equipment(assigns)

    spells_data =
      if assigns.is_spellcaster do
        cantrip_names =
          assigns.selected_cantrips
          |> Enum.map(fn id ->
            spell = Enum.find(assigns.available_cantrips, &(&1["id"] == id))

            if spell do
              get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"])
            else
              id
            end
          end)

        spell_names =
          assigns.selected_spells
          |> Enum.map(fn id ->
            spell = Enum.find(assigns.available_spells, &(&1["id"] == id))

            if spell do
              get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"])
            else
              id
            end
          end)

        %{"cantrips" => cantrip_names, "prepared" => spell_names}
      else
        %{}
      end

    CharacterData.build_character_map(%{
      name: assigns.character_name,
      class_id: assigns.selected_class["id"],
      race_id: assigns.selected_race["id"],
      background_id: assigns.selected_background["id"],
      abilities: abilities,
      class_skills: assigns.class_skills,
      equipment: equipment,
      spells: spells_data,
      armor_choice: find_armor_in_equipment(equipment)
    })
    |> Map.put("alignment", assigns.alignment)
    |> Map.put("appearance", assigns.appearance)
    |> Map.put("backstory", assigns.backstory)
  end

  def resolved_spell_limit(assigns) do
    class_id = if assigns.selected_class, do: assigns.selected_class["id"], else: nil

    case @spellcasting_classes[class_id] do
      %{spells: :wis_mod_plus_level} ->
        wis = final_ability_score(assigns, "wis")
        max(1, CharacterData.ability_modifier(wis) + 1)

      %{spells: :int_mod_plus_level} ->
        int = final_ability_score(assigns, "int")
        max(1, CharacterData.ability_modifier(int) + 1)

      %{spells: n} when is_integer(n) ->
        n

      _ ->
        assigns.spell_limit
    end
  end

  def collect_equipment(assigns) do
    class = assigns.selected_class
    background = assigns.selected_background

    class_equip = get_equip_option_text(class, assigns.class_equip_choice)

    bg_equip =
      case assigns.bg_equip_choice do
        "A" -> get_in(background, ["equipment", "optionA", "ko"]) || ""
        "B" -> get_in(background, ["equipment", "optionB", "ko"]) || ""
        _ -> ""
      end

    (parse_equipment_string(class_equip) ++ parse_equipment_string(bg_equip))
    |> Enum.uniq()
  end

  defp blank_abilities do
    Map.new(@ability_keys, &{&1, nil})
  end

  defp available_scores("standard_array", _rolled_scores, abilities) do
    remaining_scores(@standard_array, abilities)
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

  defp final_abilities_map(assigns) do
    @ability_keys
    |> Map.new(fn key ->
      value = final_ability_score(assigns, key)
      {key, value}
    end)
  end

  defp final_ability_score(assigns, key) do
    base = assigns.abilities[key] || 10
    base = if assigns.bg_ability_2 == key, do: base + 2, else: base
    base = if key in assigns.bg_ability_1, do: base + 1, else: base
    base
  end

  defp get_equip_option_text(class, choice) do
    equip = class["startingEquipment"]

    case equip do
      [%{"options" => options} | _] ->
        target = "(#{choice})"

        Enum.find_value(options, "", fn opt ->
          text =
            cond do
              is_map(opt) -> opt["ko"] || opt["en"] || ""
              is_binary(opt) -> opt
              true -> ""
            end

          if String.starts_with?(text, target) do
            String.replace(text, ~r/^\([A-Z]\)\s*/, "")
          end
        end) || ""

      _ ->
        ""
    end
  end

  defp parse_equipment_string(str) when is_binary(str) do
    str
    |> String.split([",", " 또는 ", " or "], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_equipment_string(_), do: []

  defp find_armor_in_equipment(equipment) do
    armor_data = CharacterData.armor()

    armor_list =
      cond do
        is_map(armor_data) ->
          Map.get(armor_data, "armor", []) ++ Map.get(armor_data, "shields", [])

        is_list(armor_data) ->
          armor_data

        true ->
          []
      end

    Enum.find_value(equipment, nil, fn item ->
      armor =
        Enum.find(armor_list, fn armor ->
          name_ko = get_in(armor, ["name", "ko"])
          name_en = get_in(armor, ["name", "en"])
          item == name_ko || item == name_en
        end)

      if armor do
        armor["id"]
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
