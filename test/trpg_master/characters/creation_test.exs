defmodule TrpgMaster.Characters.CreationTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Characters.Creation
  alias TrpgMaster.Rules.CharacterData

  setup_all do
    ensure_character_data_started()
    :ok
  end

  test "assign_ability/3 reclaims duplicate score assignments" do
    assigns = %{
      ability_method: "standard_array",
      rolled_scores: nil,
      abilities: %{
        "str" => 15,
        "dex" => 14,
        "con" => nil,
        "int" => nil,
        "wis" => nil,
        "cha" => nil
      }
    }

    updates = Creation.assign_ability(assigns, "dex", 15)

    assert updates.abilities["str"] == nil
    assert updates.abilities["dex"] == 15
    assert updates.available_scores == [14, 13, 12, 10, 8]
  end

  test "validate_step/1 requires background bonus choices" do
    assigns = %{
      step: 3,
      selected_background: %{"id" => "test-background"},
      bg_ability_2: nil,
      bg_ability_1: []
    }

    assert {:error, "능력치 보너스를 배정하세요. (+2 하나 또는 +1 둘)"} =
             Creation.validate_step(assigns)
  end

  test "collect_equipment/1 merges class and background selections" do
    assigns = %{
      selected_class: %{
        "startingEquipment" => [
          %{"options" => ["(A) 롱소드, 방패", "(B) 그레이트소드"]}
        ]
      },
      selected_background: %{
        "equipment" => %{
          "optionA" => %{"ko" => "배낭, 횃불"},
          "optionB" => %{"ko" => "로프"}
        }
      },
      class_equip_choice: "A",
      bg_equip_choice: "A"
    }

    assert Creation.collect_equipment(assigns) == ["롱소드", "방패", "배낭", "횃불"]
  end

  test "build_character/1 returns a character map from form assigns" do
    classes = CharacterData.classes()
    races = CharacterData.races()
    backgrounds = CharacterData.backgrounds()

    selected_class = Enum.find(classes, &(&1["id"] == "fighter")) || hd(classes)
    selected_race = hd(races)
    selected_background = hd(backgrounds)

    assigns =
      Creation.initial_state(classes, races, backgrounds)
      |> Map.merge(Creation.class_selection(selected_class))
      |> Map.put(:selected_race, selected_race)
      |> Map.merge(Creation.background_selection(selected_background))
      |> Map.put(:bg_ability_2, "int")
      |> Map.put(:abilities, %{
        "str" => 15,
        "dex" => 14,
        "con" => 13,
        "int" => 12,
        "wis" => 10,
        "cha" => 8
      })
      |> Map.put(:character_name, "테스트 영웅")

    character = Creation.build_character(assigns)

    assert character["name"] == "테스트 영웅"
    assert character["class_id"] == selected_class["id"]
    assert character["race_id"] == selected_race["id"]
    assert character["background_id"] == selected_background["id"]
    assert character["abilities"]["int"] == 14
    assert character["hp_max"] > 0
    assert is_list(character["equipment"])
  end

  defp ensure_character_data_started do
    case Process.whereis(CharacterData) do
      nil -> start_supervised!(CharacterData)
      _pid -> :ok
    end
  end
end
