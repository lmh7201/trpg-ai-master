defmodule TrpgMasterWeb.CharacterCreateFlowTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData
  alias TrpgMasterWeb.CharacterCreateFlow

  test "mount_assigns/4 prepares initial wizard state for the campaign" do
    wizard = fetch_data!(:class, "wizard")
    elf = fetch_data!(:race, "elf")
    sage = fetch_data!(:background, "sage")

    assigns = CharacterCreateFlow.mount_assigns("campaign-42", [wizard], [elf], [sage])

    assert assigns.campaign_id == "campaign-42"
    assert assigns.step == 1
    assert assigns.selected_class == nil
    assert assigns.character_name == ""
    assert assigns.classes == [wizard]
    assert assigns.races == [elf]
    assert assigns.backgrounds == [sage]
  end

  test "set_bg_ability/3 switches between +2 and +1 allocation modes" do
    assigns = %{bg_ability_2: nil, bg_ability_1: []}

    assert CharacterCreateFlow.set_bg_ability(assigns, "2", "int") == %{
             bg_ability_2: "int",
             bg_ability_1: []
           }

    assigns = %{assigns | bg_ability_2: "int", bg_ability_1: []}

    assert CharacterCreateFlow.set_bg_ability(assigns, "2", "int") == %{
             bg_ability_2: nil,
             bg_ability_1: []
           }

    assigns = %{bg_ability_2: nil, bg_ability_1: ["wis"]}

    assert CharacterCreateFlow.set_bg_ability(assigns, "1", "int") == %{
             bg_ability_1: ["wis", "int"],
             bg_ability_2: nil
           }
  end

  test "toggle_cantrip/2 respects selection limits" do
    assigns = %{selected_cantrips: ["light"], cantrip_limit: 2}

    assert CharacterCreateFlow.toggle_cantrip(assigns, "mage-hand") == %{
             selected_cantrips: ["light", "mage-hand"]
           }

    full_assigns = %{selected_cantrips: ["light", "mage-hand"], cantrip_limit: 2}

    assert CharacterCreateFlow.toggle_cantrip(full_assigns, "prestidigitation") == %{
             selected_cantrips: ["light", "mage-hand"]
           }
  end

  test "next_step/1 advances and prepares spell options when validation succeeds" do
    wizard = fetch_data!(:class, "wizard")
    elf = fetch_data!(:race, "elf")
    sage = fetch_data!(:background, "sage")

    assigns =
      Creation.initial_state([wizard], [elf], [sage])
      |> Map.merge(Creation.class_selection(wizard))
      |> Map.put(:selected_race, elf)
      |> Map.merge(Creation.background_selection(sage))
      |> Map.merge(%{
        step: 5,
        class_skills: Enum.take(get_in(wizard, ["skillProficiencies", "options", "ko"]) || [], 2),
        bg_ability_2: "int",
        abilities: %{
          "str" => 8,
          "dex" => 14,
          "con" => 13,
          "int" => 15,
          "wis" => 12,
          "cha" => 10
        }
      })

    assert {:ok, updates} = CharacterCreateFlow.next_step(assigns)
    assert updates.step == 6
    assert updates.error == nil
    assert is_list(updates.available_cantrips)
    assert is_list(updates.available_spells)
    assert updates.spell_limit > 0
  end

  test "finish/1 returns a built character when the summary step is valid" do
    assigns = summary_assigns()

    assert {:ok, character} = CharacterCreateFlow.finish(assigns)
    assert character["name"] == "엘라라"
    assert character["class_id"] == "wizard"
    assert character["race"] == display_name(assigns.selected_race)
  end

  defp summary_assigns do
    wizard = fetch_data!(:class, "wizard")
    elf = fetch_data!(:race, "elf")
    sage = fetch_data!(:background, "sage")

    base_assigns =
      Creation.initial_state([wizard], [elf], [sage])
      |> Map.merge(Creation.class_selection(wizard))
      |> Map.put(:selected_race, elf)
      |> Map.merge(Creation.background_selection(sage))
      |> Map.merge(%{
        step: 7,
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

    base_assigns
    |> Map.merge(Creation.prepare_step(base_assigns, 6))
    |> Map.put(:selected_cantrips, ["light", "mage-hand"])
    |> Map.put(:selected_spells, ["magic-missile", "shield"])
  end

  defp fetch_data!(:class, id), do: CharacterData.get_class(id) || flunk("missing class #{id}")
  defp fetch_data!(:race, id), do: CharacterData.get_race(id) || flunk("missing race #{id}")

  defp fetch_data!(:background, id),
    do: CharacterData.get_background(id) || flunk("missing background #{id}")

  defp display_name(data) do
    get_in(data, ["name", "ko"]) || get_in(data, ["name", "en"]) || data["id"]
  end
end
