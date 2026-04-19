defmodule TrpgMaster.AI.PromptBuilder.SectionsTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.PromptBuilder.Sections
  alias TrpgMaster.Campaign.State

  test "build_campaign_context/1 includes spell slot status and solo combat note" do
    state = %State{
      name: "붉은 달의 폐허",
      phase: :combat,
      turn_count: 7,
      mode: :debug,
      current_location: "지하 성소",
      characters: [
        %{
          "name" => "엘라라",
          "race" => "엘프",
          "class" => "위저드",
          "level" => 2,
          "hp_current" => 9,
          "hp_max" => 12,
          "ac" => 13,
          "spell_slots" => %{"1" => 3},
          "spell_slots_used" => %{"1" => 1}
        }
      ],
      npcs: %{},
      active_quests: [],
      combat_state: %{
        "round" => 2,
        "participants" => ["엘라라", "고블린"],
        "player_names" => ["엘라라"],
        "enemies" => [%{"name" => "고블린", "hp_current" => 4, "hp_max" => 7, "ac" => 15}]
      }
    }

    context = Sections.build_campaign_context(state)

    assert context =~ "플레이어 캐릭터 이름: 엘라라"
    assert context =~ "주문 슬롯: Lv.1: 2/3"
    assert context =~ "## 전투 진행 중"
    assert context =~ "⚠️ 솔로 플레이"
  end

  test "build_combat_phase_instruction/1 defaults enemy_turn to a generic last enemy group" do
    instruction = Sections.build_combat_phase_instruction(:enemy_turn)

    assert instruction =~ "전투 턴 진행 — 적의 턴 (마지막 적 그룹)"
    assert instruction =~ "라운드 정리 단계에서 플레이어에게 묻습니다"
  end

  test "mode_instruction/1 falls back to adventure mode for unknown values" do
    assert Sections.mode_instruction(:unknown) =~ "## 🎭 모험 모드 (현재 활성)"
  end
end
