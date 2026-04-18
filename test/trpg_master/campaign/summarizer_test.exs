defmodule TrpgMaster.Campaign.SummarizerTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{State, Summarizer}

  test "estimate_session_number/1 groups turns into coarse session buckets" do
    assert Summarizer.estimate_session_number(%State{turn_count: 0}) == 1
    assert Summarizer.estimate_session_number(%State{turn_count: 4}) == 1
    assert Summarizer.estimate_session_number(%State{turn_count: 5}) == 1
    assert Summarizer.estimate_session_number(%State{turn_count: 10}) == 2
  end

  test "meaningful_summary?/1 ignores placeholder-only content with timestamps" do
    refute Summarizer.meaningful_summary?("2026-04-18 15:20 이전 요약 없음 첫 번째 턴")

    assert Summarizer.meaningful_summary?("수호자 NPC가 파티를 의심하고 있으며 잃어버린 유물 퀘스트가 진행 중이다.")
  end

  test "format_combatants_status/1 includes ally and enemy statuses" do
    state = %State{
      characters: [
        %{
          "name" => "아리아",
          "hp_current" => 0,
          "hp_max" => 24,
          "conditions" => ["기절"]
        },
        %{"name" => "보린", "hp_current" => 15, "hp_max" => 20}
      ],
      combat_state: %{
        "player_names" => ["아리아"],
        "enemies" => [
          %{"name" => "고블린", "hp_current" => 0, "hp_max" => 7},
          %{"name" => "오우거", "hp_current" => 19, "hp_max" => 30}
        ]
      }
    }

    formatted = Summarizer.format_combatants_status(state)

    assert formatted =~ "[아군] 아리아 HP 0/24 [쓰러짐] 상태: 기절"
    assert formatted =~ "[적] 고블린 HP 0/7 [사망]"
    assert formatted =~ "[적] 오우거 HP 19/30"
    refute formatted =~ "보린"
  end
end
