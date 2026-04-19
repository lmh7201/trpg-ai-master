defmodule TrpgMaster.Rules.CharacterData.ProgressionTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Rules.CharacterData

  setup_all do
    ensure_character_data_started()
    :ok
  end

  test "xp and proficiency helpers keep expected thresholds" do
    assert CharacterData.level_for_xp(0) == 1
    assert CharacterData.level_for_xp(2_700) == 4
    assert CharacterData.xp_for_level(5) == 6_500
    assert CharacterData.proficiency_bonus_for_level(1) == 2
    assert CharacterData.proficiency_bonus_for_level(10) == 4
  end

  test "spellcasting helpers return class-specific values" do
    assert CharacterData.spell_slots_for_class_level("wizard", 3) == %{"1" => 4, "2" => 2}
    assert CharacterData.spell_slots_for_class_level("warlock", 5) == %{"3" => 2}
    assert CharacterData.cantrips_known_for_class_level("wizard", 1) == 3
    assert CharacterData.spells_known_for_class_level("bard", 2) == 5
  end

  test "ability helpers parse dice and modifiers safely" do
    assert CharacterData.parse_hit_die("d10") == 10
    assert CharacterData.parse_hit_die("D6") == 6
    assert CharacterData.parse_hit_die("weird") == 8
    assert CharacterData.ability_modifier(18) == 4
    assert CharacterData.ability_modifier(nil) == 0
  end

  test "subclass resolution matches localized names and ids" do
    subclass =
      CharacterData.subclasses_for_class("wizard")
      |> List.first()
      |> Kernel.||(flunk("wizard subclass data is required for progression test"))

    subclass_id = subclass["id"]
    subclass_name = get_in(subclass, ["name", "ko"]) || get_in(subclass, ["name", "en"])
    subclass_lookup = get_in(subclass, ["name", "en"]) || subclass_id

    assert CharacterData.resolve_subclass_id("wizard", subclass_name) == subclass_id

    assert CharacterData.resolve_subclass_name("wizard", subclass_lookup) ==
             (get_in(subclass, ["name", "ko"]) ||
                get_in(subclass, ["name", "en"]) ||
                subclass_lookup)
  end

  defp ensure_character_data_started do
    case Process.whereis(CharacterData) do
      nil -> start_supervised!(CharacterData)
      _pid -> :ok
    end
  end
end
