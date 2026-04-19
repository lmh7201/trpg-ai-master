defmodule TrpgMaster.Campaign.ToolHandler.CharacterUpdater.LevelingTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.ToolHandler.CharacterUpdater.Leveling
  alias TrpgMaster.Rules.CharacterData

  test "level_up_character marks subclass_pending when subclass choice is omitted" do
    character = %{
      "name" => "브론",
      "class_id" => "fighter",
      "level" => 2,
      "hit_die" => "d10",
      "hp_current" => 20,
      "hp_max" => 20,
      "ability_modifiers" => %{"con" => 2}
    }

    result = Leveling.level_up_character(character, %{"character_name" => "브론"})

    assert result["level"] == 3
    assert result["subclass_pending"] == true
  end

  test "level_up_character resolves feat names without duplicating existing feats" do
    feat =
      Enum.find(CharacterData.feats(), fn feat ->
        is_binary(get_in(feat, ["name", "ko"])) && is_binary(get_in(feat, ["name", "en"]))
      end) || flunk("feat data with ko/en names is required for leveling test")

    ko_name = get_in(feat, ["name", "ko"])
    en_name = get_in(feat, ["name", "en"])

    character = %{
      "name" => "아리아",
      "class_id" => "fighter",
      "level" => 3,
      "hit_die" => "d10",
      "hp_current" => 28,
      "hp_max" => 28,
      "ability_modifiers" => %{"con" => 2},
      "feats" => [ko_name]
    }

    result =
      Leveling.level_up_character(character, %{"character_name" => "아리아", "feat" => en_name})

    assert result["level"] == 4
    assert result["feats"] == [ko_name]
    refute Map.has_key?(result, "asi_pending")
  end

  test "apply_xp_gain marks subclass_pending when xp crosses a subclass level" do
    target_xp = CharacterData.xp_for_level(3)

    character = %{
      "name" => "브론",
      "class_id" => "fighter",
      "level" => 2,
      "xp" => target_xp - 50,
      "hit_die" => "d10",
      "hp_current" => 20,
      "hp_max" => 20,
      "ability_modifiers" => %{"con" => 2}
    }

    result = Leveling.apply_xp_gain(character, 50)

    assert result["xp"] == target_xp
    assert result["level"] == 3
    assert result["subclass_pending"] == true
  end
end
