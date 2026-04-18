defmodule TrpgMaster.Rules.CharacterDataTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Rules.CharacterData

  setup_all do
    ensure_character_data_started()
    :ok
  end

  test "build_character_map/1 preserves alignment and narrative fields" do
    fighter = CharacterData.get_class("fighter") || hd(CharacterData.classes())
    race = CharacterData.get_race("elf") || hd(CharacterData.races())
    background = CharacterData.get_background("sage") || hd(CharacterData.backgrounds())

    character =
      CharacterData.build_character_map(%{
        name: "세라",
        class_id: fighter["id"],
        race_id: race["id"],
        background_id: background["id"],
        abilities: %{
          "str" => 15,
          "dex" => 14,
          "con" => 13,
          "int" => 12,
          "wis" => 10,
          "cha" => 8
        },
        alignment: "혼돈 선",
        appearance: "붉은 망토와 짧은 은검을 지녔다.",
        backstory: "왕도에서 추방된 뒤 모험가가 되었다."
      })

    assert character["alignment"] == "혼돈 선"
    assert character["appearance"] == "붉은 망토와 짧은 은검을 지녔다."
    assert character["backstory"] == "왕도에서 추방된 뒤 모험가가 되었다."
  end

  test "get_character_info/2 includes alignment in summary responses" do
    character = %{
      "name" => "세라",
      "class" => "파이터",
      "race" => "엘프",
      "background" => "현자",
      "alignment" => "중립 선",
      "level" => 1,
      "hp_max" => 12,
      "hp_current" => 12,
      "ac" => 15,
      "speed" => 30
    }

    assert CharacterData.get_character_info(character, "summary") == %{
             "name" => "세라",
             "class" => "파이터",
             "race" => "엘프",
             "background" => "현자",
             "alignment" => "중립 선",
             "level" => 1,
             "hp_max" => 12,
             "hp_current" => 12,
             "ac" => 15,
             "speed" => 30
           }
  end

  defp ensure_character_data_started do
    case Process.whereis(CharacterData) do
      nil -> start_supervised!(CharacterData)
      _pid -> :ok
    end
  end
end
