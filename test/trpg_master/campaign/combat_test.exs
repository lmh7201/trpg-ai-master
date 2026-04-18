defmodule TrpgMaster.Campaign.CombatTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{Combat, State}

  test "handle_action/3 finalizes combat immediately when player result ends combat" do
    parent = self()

    state = %State{
      id: "combat-1",
      name: "전투 테스트",
      phase: :combat,
      turn_count: 4,
      exploration_history: [],
      combat_history: [],
      characters: [%{"name" => "아리아", "hp_current" => 12, "hp_max" => 18}],
      combat_state: %{
        "player_names" => ["아리아"],
        "enemies" => [%{"name" => "고블린", "hp_current" => 3, "hp_max" => 7}]
      }
    }

    result = %{text: "아리아의 일격에 고블린이 쓰러졌다.", tool_results: []}

    assert {:reply, {:ok, ^result}, new_state} =
             Combat.handle_action("검을 휘두른다", state,
               build_prompt: fn updated_state, combat_phase ->
                 assert combat_phase == :player_turn
                 assert updated_state.current_round_start_index == 0
                 "prompt:player_turn"
               end,
               build_turn_messages: fn _updated_state, message, combat_phase ->
                 assert combat_phase == :player_turn
                 [%{"role" => "user", "content" => message}]
               end,
               tools: fn -> ["combat-tool", "state-tool"] end,
               chat: fn system_prompt, history, tools, model_opts ->
                 assert system_prompt == "prompt:player_turn"
                 assert history == [%{"role" => "user", "content" => "검을 휘두른다"}]
                 assert tools == ["combat-tool", "state-tool"]
                 assert model_opts == [model: "gpt-5.4"]
                 {:ok, result}
               end,
               apply_tools: fn updated_state, [] ->
                 %{updated_state | phase: :exploration, combat_state: nil}
               end,
               generate_post_combat_summary: fn updated_state ->
                 assert List.last(updated_state.combat_history)["content"] ==
                          "아리아의 일격에 고블린이 쓰러졌다."

                 {:ok, "전투 종료 요약"}
               end,
               update_context_summary: fn updated_state ->
                 %{updated_state | context_summary: "전투 이후 맥락"}
               end,
               save_async: fn updated_state ->
                 send(parent, {:saved_state, updated_state})
               end,
               model_opts: [model: "gpt-5.4"]
             )

    assert new_state.phase == :exploration
    assert new_state.combat_state == nil
    assert new_state.context_summary == "전투 이후 맥락"
    assert new_state.post_combat_summary == "전투 종료 요약"
    assert new_state.combat_history == []

    assert new_state.exploration_history == [
             %{
               "role" => "assistant",
               "content" => "[전투 종료] 아리아의 일격에 고블린이 쓰러졌다."
             }
           ]

    assert_received {:saved_state, ^new_state}
  end

  test "handle_action/3 runs enemy turns and round summary before persisting ongoing combat" do
    parent = self()

    state = %State{
      id: "combat-2",
      name: "지하 통로",
      phase: :combat,
      turn_count: 8,
      exploration_history: [],
      combat_history: [],
      characters: [%{"name" => "아리아", "hp_current" => 14, "hp_max" => 18}],
      combat_state: %{
        "player_names" => ["아리아"],
        "enemies" => [%{"name" => "고블린", "hp_current" => 4, "hp_max" => 7}]
      }
    }

    player_result = %{text: "아리아가 화염 화살을 날렸다.", tool_results: []}
    enemy_result = %{text: "고블린이 비틀거리며 반격했다.", tool_results: []}
    round_result = %{text: "양측이 거리를 벌리며 다음 틈을 노린다.", tool_results: []}

    assert {:reply, {:ok, [^player_result, ^enemy_result, ^round_result]}, new_state} =
             Combat.handle_action("화염 화살을 쏜다", state,
               build_prompt: fn _updated_state, combat_phase ->
                 "prompt:#{inspect(combat_phase)}"
               end,
               build_turn_messages: fn _updated_state, message, combat_phase ->
                 [%{"role" => "user", "content" => "#{inspect(combat_phase)}:#{message}"}]
               end,
               tools: fn -> ["combat-tool"] end,
               chat: fn system_prompt, _history, tools, _model_opts ->
                 assert tools == ["combat-tool"]

                 case system_prompt do
                   "prompt::player_turn" -> {:ok, player_result}
                   "prompt:{:enemy_turn, \"고블린\", true}" -> {:ok, enemy_result}
                   "prompt::round_summary" -> {:ok, round_result}
                 end
               end,
               apply_tools: fn updated_state, [] -> updated_state end,
               update_combat_history_summary: fn updated_state ->
                 %{updated_state | combat_history_summary: "라운드 요약"}
               end,
               update_context_summary: fn updated_state ->
                 %{updated_state | context_summary: "전투 맥락"}
               end,
               save_async: fn updated_state ->
                 send(parent, {:saved_state, updated_state})
               end
             )

    assert new_state.phase == :combat
    assert new_state.context_summary == "전투 맥락"
    assert new_state.combat_history_summary == "라운드 요약"
    assert new_state.current_round_start_index == 0
    assert length(new_state.combat_history) == 6

    assert Enum.at(new_state.combat_history, 0) == %{"role" => "user", "content" => "화염 화살을 쏜다"}
    assert Enum.at(new_state.combat_history, 1)["content"] == player_result.text
    assert Enum.at(new_state.combat_history, 2)["synthetic"] == true
    assert Enum.at(new_state.combat_history, 3)["content"] == enemy_result.text
    assert Enum.at(new_state.combat_history, 4)["synthetic"] == true
    assert Enum.at(new_state.combat_history, 5)["content"] == round_result.text

    assert_received {:saved_state, ^new_state}
  end

  test "force_end_if_needed/1 keeps only player characters and clears combat state" do
    state = %State{
      phase: :combat,
      characters: [
        %{"name" => "아리아", "hp_current" => 0},
        %{"name" => "용병", "hp_current" => 5}
      ],
      combat_state: %{"player_names" => ["아리아"]}
    }

    result = Combat.force_end_if_needed(state)

    assert result.phase == :exploration
    assert result.combat_state == nil
    assert result.characters == [%{"name" => "아리아", "hp_current" => 0}]
  end
end
