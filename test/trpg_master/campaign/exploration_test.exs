defmodule TrpgMaster.Campaign.ExplorationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias TrpgMaster.Campaign.{Exploration, State}

  test "handle_action/3 applies tool results, clears post-combat summary, and persists state" do
    parent = self()

    state = %State{
      id: "campaign-1",
      name: "잿빛 폐허",
      phase: :exploration,
      turn_count: 3,
      post_combat_summary: "직전 전투 요약",
      exploration_history: [%{"role" => "assistant", "content" => "안개가 깔린 길이다."}],
      characters: [%{"name" => "아리아"}],
      journal_entries: [%{"text" => "폐허 입구에 도착했다."}]
    }

    result = %{
      text: "문 안은 어둡지만 발자국이 이어진다.",
      tool_results: [
        %{tool: "register_npc", input: %{"name" => "수호자", "description" => "낡은 갑옷"}}
      ]
    }

    chat =
      fn system_prompt, history, tools, model_opts ->
        assert system_prompt == "SYSTEM:campaign-1"
        assert List.last(history) == %{"role" => "user", "content" => "문을 연다"}
        assert tools == ["exploration-tool", "state-tool"]
        assert model_opts == [model: "gpt-5.4"]
        assert Process.get(:journal_entries) == state.journal_entries
        assert Process.get(:campaign_characters) == state.characters
        {:ok, result}
      end

    update_context_summary = fn updated_state ->
      %{updated_state | context_summary: "업데이트된 요약"}
    end

    save_async = fn updated_state ->
      send(parent, {:saved_state, updated_state})
    end

    assert {:reply, {:ok, ^result}, new_state} =
             Exploration.handle_action("문을 연다", state,
               build_prompt: fn updated_state ->
                 assert List.last(updated_state.exploration_history) == %{
                          "role" => "user",
                          "content" => "문을 연다"
                        }

                 "SYSTEM:#{updated_state.id}"
               end,
               build_turn_messages: fn updated_state, message ->
                 assert updated_state.turn_count == 3
                 [%{"role" => "user", "content" => message}]
               end,
               tools_for_phase: fn :exploration -> ["exploration-tool", "state-tool"] end,
               chat: chat,
               update_context_summary: update_context_summary,
               save_async: save_async,
               model_opts: [model: "gpt-5.4"]
             )

    assert new_state.post_combat_summary == nil
    assert new_state.context_summary == "업데이트된 요약"
    assert new_state.npcs["수호자"]["description"] == "낡은 갑옷"

    assert new_state.exploration_history == [
             %{"role" => "assistant", "content" => "안개가 깔린 길이다."},
             %{"role" => "user", "content" => "문을 연다"},
             %{"role" => "assistant", "content" => "문 안은 어둡지만 발자국이 이어진다."}
           ]

    assert_received {:saved_state, ^new_state}
    assert Process.get(:journal_entries) == nil
    assert Process.get(:campaign_characters) == nil
  end

  test "handle_action/3 keeps only the player message when AI call fails" do
    state = %State{
      id: "campaign-2",
      name: "잠든 숲",
      phase: :exploration,
      turn_count: 7,
      post_combat_summary: "전투 직후",
      exploration_history: [],
      characters: [%{"name" => "보린"}],
      journal_entries: [%{"text" => "숲 가장자리에 진입했다."}]
    }

    capture_log(fn ->
      assert {:reply, {:error, :timeout}, returned_state} =
               Exploration.handle_action("주변을 살핀다", state,
                 build_prompt: fn _ -> "SYSTEM" end,
                 build_turn_messages: fn _updated_state, message ->
                   [%{"role" => "user", "content" => message}]
                 end,
                 tools_for_phase: fn :exploration -> [] end,
                 chat: fn _system_prompt, _history, _tools, _model_opts ->
                   assert Process.get(:journal_entries) == state.journal_entries
                   assert Process.get(:campaign_characters) == state.characters
                   {:error, :timeout}
                 end,
                 update_context_summary: fn _ ->
                   flunk("context summary should not be updated on failure")
                 end,
                 save_async: fn _ ->
                   flunk("failed exploration action should not be persisted")
                 end
               )

      send(self(), {:returned_state, returned_state})
    end)

    assert_received {:returned_state, new_state}

    assert new_state.post_combat_summary == "전투 직후"
    assert new_state.exploration_history == [%{"role" => "user", "content" => "주변을 살핀다"}]
    assert Process.get(:journal_entries) == nil
    assert Process.get(:campaign_characters) == nil
  end
end
