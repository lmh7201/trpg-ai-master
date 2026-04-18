defmodule TrpgMaster.Campaign.ToolHandlerTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{State, ToolHandler}
  alias TrpgMaster.Rules.CharacterData

  test "update_character recalculates hp when level increases without explicit hp_max" do
    state = %State{
      characters: [
        %{
          "name" => "브론",
          "class_id" => "fighter",
          "level" => 1,
          "hit_die" => "d10",
          "hp_current" => 10,
          "hp_max" => 12,
          "proficiency_bonus" => 2,
          "ability_modifiers" => %{"con" => 2}
        }
      ]
    }

    result =
      ToolHandler.apply_one(state, %{
        tool: "update_character",
        input: %{
          "character_name" => "브론",
          "changes" => %{"level" => 2}
        }
      })

    [character] = result.characters

    assert character["level"] == 2
    assert character["hp_max"] == 20
    assert character["hp_current"] == 18
    assert character["proficiency_bonus"] == 2
  end

  test "update_character syncs enemy hp during combat even when the target is not a player character" do
    state = %State{
      characters: [%{"name" => "브론"}],
      combat_state: %{
        "enemies" => [
          %{"name" => "고블린 정찰병", "hp_current" => 9, "hp_max" => 9}
        ]
      }
    }

    result =
      ToolHandler.apply_one(state, %{
        tool: "update_character",
        input: %{
          "character_name" => "고블린 정찰병",
          "changes" => %{"hp_current" => 4, "hp_max" => 7}
        }
      })

    assert result.characters == state.characters

    assert get_in(result.combat_state, ["enemies"]) == [
             %{"name" => "고블린 정찰병", "hp_current" => 4, "hp_max" => 7}
           ]
  end

  test "level_up applies subclass selection and new spells for a caster" do
    subclass =
      CharacterData.subclasses_for_class("wizard")
      |> List.first() ||
        flunk("wizard subclass data is required for level_up test")

    subclass_name =
      get_in(subclass, ["name", "ko"]) ||
        get_in(subclass, ["name", "en"]) ||
        flunk("wizard subclass must have a name")

    state = %State{
      characters: [
        %{
          "name" => "엘라라",
          "class_id" => "wizard",
          "level" => 2,
          "xp" => 900,
          "hit_die" => "d6",
          "hp_current" => 8,
          "hp_max" => 8,
          "ability_modifiers" => %{"con" => 1},
          "spell_slots" => %{"1" => 3},
          "spell_slots_used" => %{"1" => 1}
        }
      ]
    }

    result =
      ToolHandler.apply_one(state, %{
        tool: "level_up",
        input: %{
          "character_name" => "엘라라",
          "subclass" => subclass_name,
          "new_spells" => [
            %{"name" => "Mage Hand", "level" => 0},
            %{"name" => "Magic Missile", "level" => 1}
          ]
        }
      })

    [character] = result.characters

    assert character["level"] == 3
    assert character["subclass"] == subclass_name
    assert character["subclass_id"] == subclass["id"]
    assert get_in(character, ["spells_known", "cantrips"]) == ["Mage Hand"]
    assert get_in(character, ["spells_known", "1"]) == ["Magic Missile"]
    assert character["spell_slots"] == CharacterData.spell_slots_for_class_level("wizard", 3)
  end

  test "end_combat applies xp gain and marks pending ASI choices after a level up" do
    state = %State{
      phase: :combat,
      characters: [
        %{
          "name" => "아리아",
          "class_id" => "fighter",
          "level" => 3,
          "xp" => 2_600,
          "hit_die" => "d10",
          "hp_current" => 20,
          "hp_max" => 28,
          "ability_modifiers" => %{"con" => 2}
        }
      ],
      combat_state: %{"player_names" => ["아리아"]}
    }

    result =
      ToolHandler.apply_one(state, %{
        tool: "end_combat",
        input: %{"xp" => 100}
      })

    [character] = result.characters

    assert result.phase == :exploration
    assert result.combat_state == nil
    assert character["xp"] == 2_700
    assert character["level"] == 4
    assert character["asi_pending"] == true
    assert character["hp_max"] == 36
  end
end
