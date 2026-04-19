defmodule TrpgMasterWeb.CharacterCreateComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreateComponents

  @endpoint TrpgMasterWeb.Endpoint

  defmodule ShellHarness do
    use TrpgMasterWeb, :html

    import TrpgMasterWeb.CharacterCreateComponents

    attr(:campaign_id, :string, required: true)
    attr(:step, :integer, required: true)
    attr(:steps, :list, required: true)
    attr(:error, :string, default: nil)

    def render(assigns) do
      ~H"""
      <.wizard_shell
        campaign_id={@campaign_id}
        step={@step}
        steps={@steps}
        error={@error}
      >
        <div>현재 단계 본문</div>
      </.wizard_shell>
      """
    end
  end

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

  test "race_step/1 renders selected race details and traits" do
    assigns = wizard_summary_assigns()
    first_trait = List.first(assigns.selected_race["traits"] || [])

    html = render_component(&CharacterCreateComponents.race_step/1, assigns)

    assert html =~ display_name(assigns.selected_race)
    assert html =~ "종족 특성"
    assert html =~ get_in(assigns.selected_race, ["basicTraits", "creatureType", "ko"])

    if first_trait do
      assert html =~
               (get_in(first_trait, ["name", "ko"]) || get_in(first_trait, ["name", "en"]))
    end
  end

  test "background_step/1 renders selected background details and ability choices" do
    assigns = wizard_summary_assigns()

    html = render_component(&CharacterCreateComponents.background_step/1, assigns)

    assert html =~ display_name(assigns.selected_background)
    assert html =~ "능력치 보너스 배분"
    assert html =~ get_in(assigns.selected_background, ["equipment", "optionA", "ko"])
    assert html =~ get_in(assigns.selected_background, ["equipment", "optionB", "ko"])

    assert html =~
             List.first(get_in(assigns.selected_background, ["skillProficiencies", "ko"]) || [])
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

  test "spells_step/1 renders a guidance message for non-spellcasters" do
    assigns = fighter_summary_assigns()

    html = render_component(&CharacterCreateComponents.spells_step/1, assigns)

    assert html =~ "1레벨에서 주문을 사용하지 않습니다."
    assert html =~ "다음 단계로 넘어가세요."
    refute html =~ "소마법 (Cantrip) 선택"
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

  test "wizard_shell/1 renders shared header, error banner, and step controls" do
    html =
      render_component(&ShellHarness.render/1,
        campaign_id: "campaign-42",
        step: 3,
        steps: [{1, "클래스", :class}, {2, "종족", :race}, {3, "배경", :background}],
        error: "배경을 선택해주세요"
      )

    assert html =~ "캐릭터 생성"
    assert html =~ ~s(href="/play/campaign-42")
    assert html =~ "배경을 선택해주세요"
    assert html =~ "현재 단계 본문"
    assert html =~ "cc-step-dot active"
    assert html =~ "← 이전"
    assert html =~ "다음 →"
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
