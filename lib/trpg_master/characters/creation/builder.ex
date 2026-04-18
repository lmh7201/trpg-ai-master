defmodule TrpgMaster.Characters.Creation.Builder do
  @moduledoc false

  alias TrpgMaster.Characters.Creation.Abilities
  alias TrpgMaster.Rules.CharacterData

  def build_character(assigns) do
    abilities = Abilities.final_abilities_map(assigns)
    equipment = collect_equipment(assigns)

    CharacterData.build_character_map(%{
      name: assigns.character_name,
      class_id: assigns.selected_class["id"],
      race_id: assigns.selected_race["id"],
      background_id: assigns.selected_background["id"],
      abilities: abilities,
      class_skills: assigns.class_skills,
      equipment: equipment,
      spells: build_spell_data(assigns),
      armor_choice: find_armor_in_equipment(equipment)
    })
    |> Map.put("alignment", assigns.alignment)
    |> Map.put("appearance", assigns.appearance)
    |> Map.put("backstory", assigns.backstory)
  end

  def collect_equipment(assigns) do
    class = Map.get(assigns, :selected_class)
    background = Map.get(assigns, :selected_background)

    class_equip = get_equip_option_text(class, assigns.class_equip_choice)

    bg_equip =
      case assigns.bg_equip_choice do
        "A" -> get_in(background || %{}, ["equipment", "optionA", "ko"]) || ""
        "B" -> get_in(background || %{}, ["equipment", "optionB", "ko"]) || ""
        _ -> ""
      end

    (parse_equipment_string(class_equip) ++ parse_equipment_string(bg_equip))
    |> Enum.uniq()
  end

  defp build_spell_data(assigns) do
    if assigns.is_spellcaster do
      %{
        "cantrips" => spell_names(assigns.selected_cantrips, assigns.available_cantrips),
        "prepared" => spell_names(assigns.selected_spells, assigns.available_spells)
      }
    else
      %{}
    end
  end

  defp spell_names(ids, available_spells) do
    Enum.map(ids, fn id ->
      available_spells
      |> Enum.find(&(&1["id"] == id))
      |> case do
        nil -> id
        spell -> get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"]) || id
      end
    end)
  end

  defp get_equip_option_text(class, choice) do
    equip = if is_map(class), do: class["startingEquipment"], else: nil

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
end
