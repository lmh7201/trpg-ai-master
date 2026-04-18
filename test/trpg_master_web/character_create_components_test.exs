defmodule TrpgMasterWeb.CharacterCreateComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreateComponents

  @endpoint TrpgMasterWeb.Endpoint

  test "class_step/1 renders class cards and selected class details" do
    wizard = fetch_data!(:class, "wizard")
    fighter = fetch_data!(:class, "fighter")

    assigns =
      Creation.initial_state([wizard, fighter], [], [])
      |> Map.merge(Creation.class_selection(wizard))
      |> Map.put(
        :class_skills,
        Enum.take(get_in(wizard, ["skillProficiencies", "options", "ko"]) || [], 2)
      )

    html = render_component(&CharacterCreateComponents.class_step/1, assigns)

    assert html =~ display_name(wizard)
    assert html =~ display_name(fighter)
    assert html =~ wizard["hitPointDie"]
    assert html =~ "기술 숙련 선택"

    for skill <- Enum.take(assigns.class_skills, 2) do
      assert html =~ skill
    end
  end

  test "spells_step/1 renders cantrip and spell choices for spellcasters" do
    assigns = wizard_summary_assigns()

    html = render_component(&CharacterCreateComponents.spells_step/1, assigns)

    first_cantrip = spell_name(assigns.available_cantrips, List.first(assigns.selected_cantrips))
    first_spell = spell_name(assigns.available_spells, List.first(assigns.selected_spells))

    assert html =~ "소마법 (Cantrip) 선택"
    assert html =~ "1레벨 주문 선택"
    assert html =~ first_cantrip
    assert html =~ first_spell
  end

  test "abilities_step/1 renders assigned scores with background bonuses" do
    assigns = wizard_summary_assigns()

    html = render_component(&CharacterCreateComponents.abilities_step/1, assigns)

    assert html =~ "능력치 결정"
    assert html =~ "17"
    assert html =~ "(기본 15 + 2)"
    assert html =~ "수정치: +3"
  end

  test "equipment_step/1 renders class and background equipment choices" do
    assigns = wizard_summary_assigns()

    html = render_component(&CharacterCreateComponents.equipment_step/1, assigns)

    assert html =~ "클래스 시작 장비"
    assert html =~ "배경 장비"
    assert html =~ get_in(assigns.selected_background, ["equipment", "optionA", "ko"])
    assert html =~ get_in(assigns.selected_background, ["equipment", "optionB", "ko"])
  end

  test "summary_step/1 renders final preview with derived stats and selections" do
    assigns = wizard_summary_assigns()
    preview_character = Creation.build_character(assigns)
    background_skills = get_in(assigns.selected_background, ["skillProficiencies", "ko"]) || []
    first_cantrip = spell_name(assigns.available_cantrips, List.first(assigns.selected_cantrips))
    first_spell = spell_name(assigns.available_spells, List.first(assigns.selected_spells))

    html = render_component(&CharacterCreateComponents.summary_step/1, assigns)

    assert html =~ assigns.character_name
    assert html =~ display_name(assigns.selected_race)
    assert html =~ display_name(assigns.selected_class)
    assert html =~ display_name(assigns.selected_background)
    assert html =~ to_string(preview_character["hp_max"])
    assert html =~ to_string(preview_character["ac"])
    assert html =~ to_string(preview_character["abilities"]["int"])
    assert html =~ List.first(assigns.class_skills)
    assert html =~ List.first(background_skills)
    assert html =~ first_cantrip
    assert html =~ first_spell
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
