defmodule TrpgMaster.Campaign.ServerActionsTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{ServerActions, State}

  describe "set_character/2" do
    test "캐릭터 리스트를 교체하고 등록 로그를 만든다" do
      state = %State{id: "c1", characters: [%{"name" => "old"}]}
      character = %{"name" => "아리아"}

      {new_state, log} = ServerActions.set_character(state, character)

      assert new_state.characters == [character]
      assert log =~ "캐릭터 등록"
      assert log =~ "아리아"
    end
  end

  describe "set_mode/2" do
    test "허용된 모드로 변경하고 로그를 만든다" do
      state = %State{id: "c1", mode: :adventure}

      {new_state, log} = ServerActions.set_mode(state, :debug)

      assert new_state.mode == :debug
      assert log =~ "모드 변경"
      assert log =~ "adventure"
      assert log =~ "debug"
    end

    test "허용되지 않은 모드는 FunctionClauseError를 낸다" do
      state = %State{id: "c1"}

      assert_raise FunctionClauseError, fn ->
        ServerActions.set_mode(state, :invalid)
      end
    end
  end

  describe "set_model/2" do
    test "모델 ID를 변경하고 로그를 만든다" do
      state = %State{id: "c1", ai_model: "old-model"}

      {new_state, log} = ServerActions.set_model(state, "new-model")

      assert new_state.ai_model == "new-model"
      assert log =~ "AI 모델 변경"
    end

    test "nil 모델 ID도 허용한다" do
      state = %State{id: "c1", ai_model: "old-model"}

      {new_state, _log} = ServerActions.set_model(state, nil)

      assert new_state.ai_model == nil
    end
  end

  describe "clear_session_state/1" do
    test "히스토리/요약 필드를 초기화한다" do
      state = %State{
        id: "c1",
        exploration_history: [%{"role" => "user", "content" => "hi"}],
        combat_history: [%{"role" => "user", "content" => "atk"}],
        combat_history_summary: "전투 요약",
        post_combat_summary: "전투 후",
        context_summary: "컨텍스트"
      }

      cleared = ServerActions.clear_session_state(state)

      assert cleared.exploration_history == []
      assert cleared.combat_history == []
      assert cleared.combat_history_summary == nil
      assert cleared.post_combat_summary == nil
      assert cleared.context_summary == nil
    end

    test "다른 필드(id, name, characters)는 보존한다" do
      state = %State{
        id: "c1",
        name: "Test",
        characters: [%{"name" => "A"}],
        exploration_history: [:x]
      }

      cleared = ServerActions.clear_session_state(state)

      assert cleared.id == "c1"
      assert cleared.name == "Test"
      assert cleared.characters == [%{"name" => "A"}]
    end
  end

  describe "advance_turn/1" do
    test "turn_count를 1 증가시킨다" do
      state = %State{turn_count: 5}
      assert ServerActions.advance_turn(state).turn_count == 6
    end

    test "0에서 시작하는 경우 1이 된다" do
      state = %State{turn_count: 0}
      assert ServerActions.advance_turn(state).turn_count == 1
    end
  end
end
