defmodule TrpgMaster.AI.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.PromptBuilder
  alias TrpgMaster.Campaign.State

  test "build/2 includes key sections for the current campaign state" do
    state = %State{
      name: "붉은 달의 폐허",
      phase: :combat,
      turn_count: 7,
      mode: :debug,
      current_location: "지하 성소",
      context_summary: "이전에는 폐허 입구를 조사했다.",
      combat_history_summary: "고블린 무리가 엄폐 뒤에서 버텼다.",
      post_combat_summary: "직전 전투에서 늑대 두 마리를 쓰러뜨렸다.",
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
      npcs: %{
        "경비병" => %{"description" => "겁에 질린 표정", "location" => "문 옆"}
      },
      active_quests: [
        %{"name" => "성소 조사", "status" => "진행중", "description" => "제단의 비밀을 밝혀라"}
      ],
      combat_state: %{
        "round" => 2,
        "participants" => ["엘라라", "고블린"],
        "player_names" => ["엘라라"],
        "enemies" => [%{"name" => "고블린", "hp_current" => 4, "hp_max" => 7, "ac" => 15}]
      }
    }

    prompt = PromptBuilder.build(state, combat_phase: :player_turn)

    assert prompt =~ "현재 캠페인 상황"
    assert prompt =~ "이전 대화 요약"
    assert prompt =~ "현재 전투 요약"
    assert prompt =~ "직전 전투 요약"
    assert prompt =~ "전투 턴 진행 — 플레이어 턴"
    assert prompt =~ "주요 NPC"
    assert prompt =~ "진행 중인 퀘스트"
    assert prompt =~ "전투 진행 중"
    assert prompt =~ "## 🔧 디버그 모드 (현재 활성)"
  end

  test "build_turn_messages/3 keeps recent exploration messages and appends current user input" do
    state = %State{
      phase: :exploration,
      exploration_history: [
        %{"role" => "assistant", "content" => "오래된 응답"},
        %{"role" => "user", "content" => "둘러본다"},
        %{"role" => "assistant", "content" => "서가가 보인다"},
        %{"role" => "user", "content" => "책을 집는다"},
        %{"role" => "assistant", "content" => "먼지가 흩날린다"},
        %{"role" => "user", "content" => "주문서를 펼친다"}
      ]
    }

    messages = PromptBuilder.build_turn_messages(state, "문장을 읽는다")

    assert List.last(messages) == %{"role" => "user", "content" => "문장을 읽는다"}
    assert Enum.count(messages) == 6
    refute Enum.at(messages, 0) == %{"role" => "assistant", "content" => "오래된 응답"}
  end

  test "build_turn_messages/3 uses current combat round history and strips synthetic markers" do
    state = %State{
      phase: :combat,
      current_round_start_index: 2,
      exploration_history: [
        %{"role" => "assistant", "content" => "이전 탐험 요약"},
        %{"role" => "user", "content" => "계단을 내려간다"}
      ],
      combat_history: [
        %{"role" => "user", "content" => "이전 라운드 행동"},
        %{"role" => "assistant", "content" => "이전 라운드 결과"},
        %{"role" => "user", "content" => "화염 화살을 쏜다"},
        %{"role" => "assistant", "content" => "고블린이 비틀거린다", "synthetic" => true}
      ]
    }

    messages = PromptBuilder.build_turn_messages(state, "무시되는 메시지")

    assert messages == [
             %{"role" => "user", "content" => "계단을 내려간다"},
             %{"role" => "user", "content" => "화염 화살을 쏜다"},
             %{"role" => "assistant", "content" => "고블린이 비틀거린다"}
           ]
  end

  test "build_messages_with_summary/3 keeps only the recent sliding window" do
    history =
      Enum.map(1..8, fn idx ->
        %{"role" => if(rem(idx, 2) == 0, do: "assistant", else: "user"), "content" => "msg#{idx}"}
      end)

    messages = PromptBuilder.build_messages_with_summary("현재 입력", "요약", history)

    assert Enum.map(messages, & &1["content"]) == ["msg5", "msg6", "msg7", "msg8", "현재 입력"]
  end
end
