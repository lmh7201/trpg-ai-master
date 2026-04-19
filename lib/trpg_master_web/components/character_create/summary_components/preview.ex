defmodule TrpgMasterWeb.CharacterCreate.SummaryComponents.Preview do
  @moduledoc false

  alias TrpgMaster.Characters.Creation

  def build(assigns) do
    preview_character = Creation.build_character(assigns)

    %{
      preview_character: preview_character,
      final_abilities: preview_character["abilities"] || %{},
      preview_name: preview_name(assigns.character_name),
      preview_line: preview_line(assigns),
      speed_display: speed_display(assigns.selected_race),
      skill_names: skill_names(assigns),
      cantrip_names:
        spell_names(assigns.available_cantrips, assigns.selected_cantrips, assigns.is_spellcaster),
      spell_names:
        spell_names(assigns.available_spells, assigns.selected_spells, assigns.is_spellcaster)
    }
  end

  defp preview_name(name) when is_binary(name) and name != "", do: name
  defp preview_name(_name), do: "???"

  defp preview_line(assigns) do
    "#{display_name(assigns.selected_race)} #{display_name(assigns.selected_class)} Lv.1 | 배경: #{display_name(assigns.selected_background)}"
  end

  defp speed_display(nil), do: "30피트"
  defp speed_display(race), do: get_in(race, ["basicTraits", "speed", "ko"]) || "30피트"

  defp skill_names(assigns) do
    (assigns.class_skills || []) ++ background_skills(assigns.selected_background)
  end

  defp background_skills(nil), do: []
  defp background_skills(%{"skillProficiencies" => %{"ko" => skills}}), do: skills
  defp background_skills(_background), do: []

  defp spell_names(_spells, _selected_ids, false), do: []

  defp spell_names(spells, selected_ids, true) do
    (selected_ids || [])
    |> Enum.map(&find_spell_name(spells, &1))
  end

  defp find_spell_name(spells, id) do
    case Enum.find(spells || [], &(&1["id"] == id)) do
      nil -> id
      spell -> get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"])
    end
  end

  defp display_name(nil), do: "?"

  defp display_name(data) do
    get_in(data, ["name", "ko"]) || get_in(data, ["name", "en"]) || data["id"] || "?"
  end
end
