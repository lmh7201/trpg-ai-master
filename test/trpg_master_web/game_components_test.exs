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

  test "campaign_header/1 renders campaign metadata and current controls" do
    html =
      render_component(&GameComponents.campaign_header/1,
        campaign_id: "campaign-42",
        campaign_name: "붉은 달의 폐허",
        phase: :combat,
        ai_model: "gpt-5.4",
        mode: :debug,
        loading: true
      )

    assert html =~ "붉은 달의 폐허"
    assert html =~ "전투"
    assert html =~ ~s(href="/history/campaign-42")
    assert html =~ "mode-debug"
    assert html =~ "aria-label=\"GPT\""
    assert html =~ ~s(title="세션 종료")
    assert html =~ "disabled"
  end

  test "model_selector_modal/1 groups models and shows availability badges" do
    html =
      render_component(&GameComponents.model_selector_modal/1,
        available_models: [
          %{
            id: "claude-sonnet-4-6",
            name: "Claude Sonnet 4.6",
            provider: :anthropic,
            env: "ANTHROPIC_API_KEY",
            available: true
          },
          %{
            id: "gpt-5.4",
            name: "GPT-5.4",
            provider: :openai,
            env: "OPENAI_API_KEY",
            available: true
          },
          %{
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash",
            provider: :gemini,
            env: "GOOGLE_API_KEY",
            available: false
          }
        ],
        ai_model: "gpt-5.4"
      )

    assert html =~ "Anthropic"
    assert html =~ "OpenAI"
    assert html =~ "Google Gemini"
    assert html =~ "GPT-5.4"
    assert html =~ "사용 중"
    assert html =~ "API 키 미설정"
    assert html =~ ~s(phx-value-model="gemini-2.5-flash")
    assert html =~ "GOOGLE_API_KEY 환경변수가 설정되지 않았습니다."
  end

  test "campaign_status_bars/1 renders one bar per player character during combat" do
    html =
      render_component(&GameComponents.campaign_status_bars/1,
        characters: [
          %{"name" => "아리아", "hp_current" => 18, "hp_max" => 24, "ac" => 15},
          %{"name" => "보린", "hp_current" => 30, "hp_max" => 30, "ac" => 17}
        ],
        character: %{"name" => "아리아", "hp_current" => 18, "hp_max" => 24, "ac" => 15},
        location: "폐허 안뜰",
        phase: :combat,
        combat_state: %{"round" => 3, "participants" => ["아리아", "고블린"]},
        mode: :debug
      )

    assert html =~ "아리아"
    assert html =~ "보린"
    assert html =~ "폐허 안뜰"
    assert html =~ "3라운드"
    assert html =~ "디버그"
  end

  test "status_bar/1 renders spell slot summary for a single character" do
    html =
      render_component(&GameComponents.status_bar/1,
        character: %{
          "name" => "엘라라",
          "hp_current" => 22,
          "hp_max" => 30,
          "ac" => 15,
          "spell_slots" => %{"1" => 4, "2" => 3},
          "spell_slots_used" => %{"1" => 2, "2" => 1}
        },
        location: "마탑",
        phase: :exploration,
        combat_state: nil,
        mode: :adventure
      )

    assert html =~ "엘라라"
    assert html =~ "22/30"
    assert html =~ "AC"
    assert html =~ "주문 슬롯 4/7"
    assert html =~ "마탑"
  end
end
