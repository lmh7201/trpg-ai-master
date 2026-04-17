defmodule TrpgMasterWeb.GameComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TrpgMasterWeb.GameComponents

  @endpoint TrpgMasterWeb.Endpoint

  test "character_sheet_modal/1 renders detailed character information" do
    html =
      render_component(&GameComponents.character_sheet_modal/1,
        character: %{
          "name" => "엘라라",
          "class" => "위저드",
          "subclass" => "예지학파",
          "level" => 5,
          "race" => "엘프",
          "background" => "현자",
          "alignment" => "중립 선",
          "appearance" => "은빛 머리카락과 푸른 망토를 걸쳤다.",
          "backstory" => "별을 연구하던 마법사였다.",
          "abilities" => %{
            "str" => 8,
            "dex" => 14,
            "con" => 12,
            "int" => 18,
            "wis" => 13,
            "cha" => 10
          },
          "hp_current" => 22,
          "hp_max" => 30,
          "ac" => 15,
          "speed" => 30,
          "spell_slots" => %{"1" => 4, "2" => 3},
          "spell_slots_used" => %{"1" => 2, "2" => 1},
          "spells_known" => %{
            "cantrips" => ["Mage Hand", "Light"],
            "1" => ["Magic Missile", "Shield"],
            "2" => ["Misty Step"]
          },
          "inventory" => ["주문서", %{"name" => "치유 물약"}],
          "class_features" => [
            %{"level" => 1, "name" => "Arcane Recovery"},
            %{"level" => 2, "name" => "Spellcasting"}
          ],
          "subclass_features" => [
            %{"level" => 2, "name" => "Portent"}
          ],
          "feats" => ["War Caster"],
          "background_feat" => "Researcher",
          "conditions" => ["집중"]
        }
      )

    assert html =~ ~s(id="character-modal")
    assert html =~ "엘라라"
    assert html =~ "위저드 (예지학파) · 5레벨"
    assert html =~ "은빛 머리카락과 푸른 망토를 걸쳤다."
    assert html =~ "별을 연구하던 마법사였다."
    assert html =~ "-1"
    assert html =~ "+4"
    assert html =~ "22/30"
    assert html =~ "Lv.1"
    assert html =~ "2/4"
    assert html =~ "Magic Missile"
    assert html =~ "주문서"
    assert html =~ "치유 물약"
    assert html =~ "Arcane Recovery"
    assert html =~ "Portent"
    assert html =~ "War Caster"
    assert html =~ "Researcher"
    assert html =~ "집중"
  end

  test "character_sheet_modal/1 hides optional sections when data is absent" do
    html =
      render_component(&GameComponents.character_sheet_modal/1,
        character: %{
          "name" => "브론",
          "class" => "파이터",
          "level" => 2,
          "abilities" => %{"str" => 16},
          "hp_current" => 18,
          "hp_max" => 18,
          "ac" => 17,
          "inventory" => []
        }
      )

    assert html =~ "브론"
    assert html =~ "파이터 · 2레벨"
    assert html =~ "소지품 없음"
    refute html =~ "외모"
    refute html =~ "배경 스토리"
    refute html =~ "주문 슬롯"
    refute html =~ "알고 있는 주문"
    refute html =~ "클래스 피처"
    refute html =~ "상태이상"
  end
end
