defmodule TrpgMasterWeb.CharacterCreate.SummaryPreviewTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreate.SummaryComponents.Preview

  test "build/1 prepares derived summary labels and spell names" do
    assigns = wizard_summary_assigns()

    preview = Preview.build(assigns)

    assert preview.preview_name == "엘라라"
    assert preview.preview_line =~ display_name(assigns.selected_race)
    assert preview.preview_line =~ display_name(assigns.selected_class)
    assert preview.preview_line =~ display_name(assigns.selected_background)
    assert preview.speed_display == get_in(assigns.selected_race, ["basicTraits", "speed", "ko"])
    assert List.first(preview.skill_names) == List.first(assigns.class_skills)

    assert List.first(preview.cantrip_names) ==
             spell_name(assigns.available_cantrips, List.first(assigns.selected_cantrips))

    assert List.first(preview.spell_names) ==
             spell_name(assigns.available_spells, List.first(assigns.selected_spells))
  end

  test "build/1 hides spell names for non-spellcasters" do
    assigns = fighter_summary_assigns()

    preview = Preview.build(assigns)

    assert preview.preview_name == "브론"
    assert preview.cantrip_names == []
    assert preview.spell_names == []
  end

  defp wizard_summary_assigns do
    wizard = fetch_data!(:class, "wizard")
    fighter = fetch_data!(:class, "fighter")
    elf = fetch_data!(:race, "elf")
    sage = fetch_data!(:background, "sage")

    base_assigns =
      Creation.initial_state([wizard, fighter], [elf], [sage])
      |> Map.merge(Creation.class_selection(wizard))
      |> Map.put(:selected_race, elf)
      |> Map.merge(Creation.background_selection(sage))
      |> Map.merge(%{
        class_skills: Enum.take(get_in(wizard, ["skillProficiencies", "options", "ko"]) || [], 2),
        bg_ability_2: "int",
        abilities: %{
          "str" => 8,
          "dex" => 14,
          "con" => 13,
          "int" => 15,
          "wis" => 12,
          "cha" => 10
        },
        character_name: "엘라라",
        alignment: "중립 선",
        appearance: "푸른 망토와 은빛 머리카락을 지녔다.",
        backstory: "별과 마법을 연구하던 학자였다."
      })

    spell_assigns =
      base_assigns
      |> Map.merge(Creation.prepare_step(base_assigns, 6))

    spell_assigns
    |> Map.put(:selected_cantrips, take_spell_ids(spell_assigns.available_cantrips, 2))
    |> Map.put(:selected_spells, take_spell_ids(spell_assigns.available_spells, 2))
  end

  defp fighter_summary_assigns do
    fighter = fetch_data!(:class, "fighter")
    elf = fetch_data!(:race, "elf")
    sage = fetch_data!(:background, "sage")

    base_assigns =
      Creation.initial_state([fighter], [elf], [sage])
      |> Map.merge(Creation.class_selection(fighter))
      |> Map.put(:selected_race, elf)
      |> Map.merge(Creation.background_selection(sage))
      |> Map.merge(%{
        class_skills:
          Enum.take(get_in(fighter, ["skillProficiencies", "options", "ko"]) || [], 2),
        bg_ability_2: "str",
        abilities: %{
          "str" => 15,
          "dex" => 14,
          "con" => 13,
          "int" => 10,
          "wis" => 12,
          "cha" => 8
        },
        character_name: "브론"
      })

    base_assigns
    |> Map.merge(Creation.prepare_step(base_assigns, 6))
  end

  defp fetch_data!(:class, id), do: CharacterData.get_class(id) || flunk("missing class #{id}")
  defp fetch_data!(:race, id), do: CharacterData.get_race(id) || flunk("missing race #{id}")

  defp fetch_data!(:background, id),
    do: CharacterData.get_background(id) || flunk("missing background #{id}")

  defp display_name(data) do
    get_in(data, ["name", "ko"]) || get_in(data, ["name", "en"]) || data["id"]
  end

  defp take_spell_ids(spells, count) do
    spells
    |> Enum.take(count)
    |> Enum.map(& &1["id"])
  end

  defp spell_name(spells, id) do
    case Enum.find(spells, &(&1["id"] == id)) do
      nil -> id
      spell -> get_in(spell, ["name", "ko"]) || get_in(spell, ["name", "en"])
    end
  end
end
