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

  defp restore_data_dir(nil), do: Application.delete_env(:trpg_master, :data_dir)
  defp restore_data_dir(path), do: Application.put_env(:trpg_master, :data_dir, path)
end
