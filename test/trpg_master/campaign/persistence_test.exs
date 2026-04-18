defmodule TrpgMaster.Campaign.PersistenceTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Campaign.{Persistence, State}

  setup do
    original_data_dir = Application.get_env(:trpg_master, :data_dir)

    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "trpg_master_persistence_test_#{System.unique_integer([:positive])}"
      )

    File.rm_rf(tmp_dir)
    File.mkdir_p!(tmp_dir)
    Application.put_env(:trpg_master, :data_dir, tmp_dir)

    on_exit(fn ->
      restore_data_dir(original_data_dir)
      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "save/1 and load/1 round-trip campaign state" do
    campaign_id = "campaign-#{System.unique_integer([:positive])}"

    state = %State{
      id: campaign_id,
      name: "Persistence Test",
      characters: [%{"name" => "아리아", "level" => 2, "hp_current" => 12}],
      npcs: %{"상인" => %{"name" => "상인", "location" => "시장"}},
      current_location: "고대 유적",
      active_quests: [%{"name" => "잃어버린 유물", "status" => "진행중"}],
      exploration_history: [%{"role" => "user", "content" => "유적으로 들어간다."}],
      combat_history: [%{"role" => "assistant", "content" => "전투가 시작되었다."}],
      journal_entries: [%{"text" => "숨겨진 문양 발견", "category" => "clue"}],
      context_summary: "이전 모험 요약",
      ai_model: "gpt-5.4"
    }

    assert :ok = Persistence.save(state)
    assert {:ok, loaded_state} = Persistence.load(campaign_id)

    assert loaded_state.id == state.id
    assert loaded_state.name == state.name
    assert loaded_state.characters == state.characters
    assert loaded_state.npcs == state.npcs
    assert loaded_state.current_location == state.current_location
    assert loaded_state.active_quests == state.active_quests
    assert loaded_state.exploration_history == state.exploration_history
    assert loaded_state.combat_history == state.combat_history
    assert loaded_state.journal_entries == state.journal_entries
    assert loaded_state.context_summary == state.context_summary
    assert loaded_state.ai_model == state.ai_model
  end

  test "load_campaign_history/1 returns summary metadata and logs for history view" do
    campaign_id = "campaign-#{System.unique_integer([:positive])}"

    state = %State{
      id: campaign_id,
      name: "History View Test"
    }

    assert :ok = Persistence.save(state)
    assert :ok = Persistence.append_session_log(state, 1, "첫 세션 요약")
    assert :ok = Persistence.append_summary_log(campaign_id, "AI 요약 로그")

    assert {:ok, history} = Persistence.load_campaign_history(campaign_id)
    assert history.name == "History View Test"

    assert [session] = history.sessions
    assert session =~ "# 세션 1 — #{Date.utc_today() |> Date.to_iso8601()}"
    assert session =~ "첫 세션 요약"
    assert session =~ "## 파티 현황 (자동 기록)"

    assert [%{"summary" => "AI 요약 로그", "timestamp" => timestamp}] = history.summary_logs
    assert is_binary(timestamp)
  end

  test "load_campaign_history/1 returns not_found when campaign summary is missing" do
    campaign_id = "missing-#{System.unique_integer([:positive])}"

    assert {:error, :not_found} = Persistence.load_campaign_history(campaign_id)
  end

  test "list_campaigns/0 returns saved campaigns sorted by updated_at descending" do
    older_id = "campaign-older-#{System.unique_integer([:positive])}"
    newer_id = "campaign-newer-#{System.unique_integer([:positive])}"

    older_path = write_campaign_summary(older_id, "Older Campaign", "2026-04-18T10:00:00Z")
    _newer_path = write_campaign_summary(newer_id, "Newer Campaign", "2026-04-18T12:00:00Z")

    campaigns = Persistence.list_campaigns()

    assert Enum.take(campaigns, 2) == [
             %{id: newer_id, name: "Newer Campaign", updated_at: "2026-04-18T12:00:00Z"},
             %{id: older_id, name: "Older Campaign", updated_at: "2026-04-18T10:00:00Z"}
           ]

    assert File.exists?(older_path)
  end

  test "load/1 falls back to legacy conversation history file" do
    campaign_id = "legacy-#{System.unique_integer([:positive])}"

    state = %State{
      id: campaign_id,
      name: "Legacy Migration Test",
      exploration_history: [%{"role" => "assistant", "content" => "기존 대화 기록"}]
    }

    assert :ok = Persistence.save(state)

    data_dir = Application.fetch_env!(:trpg_master, :data_dir)
    campaign_dir = Path.join([data_dir, "campaigns", campaign_id])
    exploration_path = Path.join(campaign_dir, "exploration_history.json")
    legacy_path = Path.join(campaign_dir, "conversation_history.json")

    assert :ok = File.rename(exploration_path, legacy_path)
    assert {:ok, loaded_state} = Persistence.load(campaign_id)
    assert loaded_state.exploration_history == state.exploration_history
  end

  defp restore_data_dir(nil), do: Application.delete_env(:trpg_master, :data_dir)
  defp restore_data_dir(path), do: Application.put_env(:trpg_master, :data_dir, path)

  defp write_campaign_summary(campaign_id, name, updated_at) do
    data_dir = Application.fetch_env!(:trpg_master, :data_dir)
    campaign_dir = Path.join([data_dir, "campaigns", campaign_id])
    summary_path = Path.join(campaign_dir, "campaign-summary.json")

    File.mkdir_p!(campaign_dir)

    File.write!(
      summary_path,
      Jason.encode!(%{
        "id" => campaign_id,
        "name" => name,
        "updated_at" => updated_at
      })
    )

    summary_path
  end
end
