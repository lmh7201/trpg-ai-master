defmodule TrpgMaster.Campaign.SummarizerUpdateTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{State, Summarizer.Update}

  test "context_summary/3 appends the previous meaningful summary before replacing it" do
    Process.put(:summary_log_entries, [])

    on_exit(fn ->
      Process.delete(:summary_log_entries)
    end)

    state = %State{
      id: "camp-1",
      context_summary: "수호자 NPC가 파티를 의심하고 있으며 유물 퀘스트가 진행 중이다."
    }

    updated_state =
      Update.context_summary(state, {:ok, "새 요약"},
        append_summary_log: fn campaign_id, summary ->
          Process.put(
            :summary_log_entries,
            Process.get(:summary_log_entries, []) ++ [{campaign_id, summary}]
          )
        end
      )

    assert updated_state.context_summary == "새 요약"

    assert Process.get(:summary_log_entries) == [
             {"camp-1", "수호자 NPC가 파티를 의심하고 있으며 유물 퀘스트가 진행 중이다."}
           ]
  end

  test "context_summary/3 skips placeholder summaries when appending logs" do
    Process.put(:summary_log_entries, [])

    on_exit(fn ->
      Process.delete(:summary_log_entries)
    end)

    state = %State{
      id: "camp-2",
      context_summary: "2026-04-18 15:20 이전 요약 없음 첫 번째 턴"
    }

    _updated_state =
      Update.context_summary(state, {:ok, "새 요약"},
        append_summary_log: fn campaign_id, summary ->
          Process.put(
            :summary_log_entries,
            Process.get(:summary_log_entries, []) ++ [{campaign_id, summary}]
          )
        end
      )

    assert Process.get(:summary_log_entries) == []
  end

  test "combat_history_summary/2 updates the state on success" do
    state = %State{id: "camp-3", combat_history_summary: nil}

    updated_state = Update.combat_history_summary(state, {:ok, "전투 요약"})

    assert updated_state.combat_history_summary == "전투 요약"
  end
end
