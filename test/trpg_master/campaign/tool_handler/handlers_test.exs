defmodule TrpgMaster.Campaign.ToolHandler.HandlersTest do
  @moduledoc """
  도구별 handler 모듈(NpcHandler, QuestHandler, LocationHandler, JournalHandler,
  CombatHandler)의 단위 테스트.
  """

  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.State

  alias TrpgMaster.Campaign.ToolHandler.{
    CombatHandler,
    JournalHandler,
    LocationHandler,
    NpcHandler,
    QuestHandler
  }

  # ── NpcHandler ───────────────────────────────────────────────────────────

  describe "NpcHandler.apply/2" do
    test "새 NPC를 등록한다" do
      state = %State{id: "c1", npcs: %{}}

      input = %{
        "name" => "브론",
        "description" => "여관 주인",
        "disposition" => "friendly"
      }

      result = NpcHandler.apply(state, input)

      assert %{"name" => "브론", "description" => "여관 주인"} = result.npcs["브론"]
    end

    test "이름이 비어 있으면 state를 그대로 돌려준다" do
      state = %State{id: "c1", npcs: %{"X" => %{}}}

      assert NpcHandler.apply(state, %{"name" => ""}) == state
      assert NpcHandler.apply(state, %{"name" => "   "}) == state
      assert NpcHandler.apply(state, %{"name" => nil}) == state
    end

    test "기존 NPC는 필드를 머지한다 (nil은 덮어쓰지 않음)" do
      state = %State{
        id: "c1",
        npcs: %{
          "브론" => %{
            "name" => "브론",
            "description" => "기존 설명",
            "disposition" => "neutral"
          }
        }
      }

      result =
        NpcHandler.apply(state, %{
          "name" => "브론",
          "disposition" => "friendly",
          "description" => nil
        })

      assert result.npcs["브론"]["disposition"] == "friendly"
      assert result.npcs["브론"]["description"] == "기존 설명"
    end

    test "이름 앞뒤 공백은 제거된다" do
      state = %State{id: "c1", npcs: %{}}
      result = NpcHandler.apply(state, %{"name" => "  엘라라  "})

      assert Map.has_key?(result.npcs, "엘라라")
      refute Map.has_key?(result.npcs, "  엘라라  ")
    end
  end

  # ── QuestHandler ─────────────────────────────────────────────────────────

  describe "QuestHandler.apply/2" do
    test "새 퀘스트를 추가한다" do
      state = %State{id: "c1", active_quests: []}

      input = %{
        "quest_name" => "잃어버린 반지",
        "status" => "진행",
        "description" => "할머니의 반지를 찾아라"
      }

      result = QuestHandler.apply(state, input)

      assert [quest] = result.active_quests
      assert quest["name"] == "잃어버린 반지"
      assert quest["status"] == "진행"
      assert quest["description"] == "할머니의 반지를 찾아라"
    end

    test "퀘스트 이름이 비어 있으면 무시한다" do
      state = %State{id: "c1", active_quests: [%{"name" => "Q"}]}

      assert QuestHandler.apply(state, %{"quest_name" => ""}) == state
      assert QuestHandler.apply(state, %{"quest_name" => nil}) == state
    end

    test "status 미지정 시 기본값은 '발견'이다" do
      state = %State{id: "c1", active_quests: []}
      result = QuestHandler.apply(state, %{"quest_name" => "새 퀘스트"})

      assert [%{"status" => "발견"}] = result.active_quests
    end

    test "기존 퀘스트는 필드를 머지한다 (nil은 덮어쓰지 않음)" do
      state = %State{
        id: "c1",
        active_quests: [
          %{
            "name" => "잃어버린 반지",
            "status" => "진행",
            "description" => "원래 설명",
            "notes" => "원래 노트"
          }
        ]
      }

      result =
        QuestHandler.apply(state, %{
          "quest_name" => "잃어버린 반지",
          "status" => "완료",
          "description" => nil,
          "notes" => "새 노트"
        })

      assert [quest] = result.active_quests
      assert quest["status"] == "완료"
      assert quest["description"] == "원래 설명"
      assert quest["notes"] == "새 노트"
    end
  end

  # ── LocationHandler ──────────────────────────────────────────────────────

  describe "LocationHandler.apply/2" do
    test "위치를 갱신한다" do
      state = %State{id: "c1", current_location: "마을"}
      result = LocationHandler.apply(state, %{"location_name" => "숲"})

      assert result.current_location == "숲"
    end

    test "위치 이름이 비어 있으면 무시한다" do
      state = %State{id: "c1", current_location: "마을"}

      assert LocationHandler.apply(state, %{"location_name" => ""}) == state
      assert LocationHandler.apply(state, %{"location_name" => "   "}) == state
      assert LocationHandler.apply(state, %{"location_name" => nil}) == state
    end

    test "이름 앞뒤 공백을 제거한다" do
      state = %State{id: "c1", current_location: "마을"}
      result = LocationHandler.apply(state, %{"location_name" => "  광장  "})

      assert result.current_location == "광장"
    end
  end

  # ── JournalHandler ───────────────────────────────────────────────────────

  describe "JournalHandler.write/2" do
    test "저널 엔트리를 기록한다" do
      state = %State{id: "c1", journal_entries: []}

      result =
        JournalHandler.write(state, %{
          "entry" => "첫 번째 기록",
          "category" => "quest"
        })

      assert [entry] = result.journal_entries
      assert entry["text"] == "첫 번째 기록"
      assert entry["category"] == "quest"
      assert is_binary(entry["timestamp"])
    end

    test "category가 없으면 'note'를 사용한다" do
      state = %State{id: "c1", journal_entries: []}
      result = JournalHandler.write(state, %{"entry" => "메모"})

      assert [%{"category" => "note"}] = result.journal_entries
    end

    test "entry가 비어 있으면 무시한다" do
      state = %State{id: "c1", journal_entries: [%{"text" => "기존"}]}

      assert JournalHandler.write(state, %{"entry" => ""}) == state
      assert JournalHandler.write(state, %{"entry" => nil}) == state
      assert JournalHandler.write(state, %{"entry" => "   "}) == state
    end

    test "엔트리 리스트는 뒤에 추가된다" do
      state = %State{id: "c1", journal_entries: [%{"text" => "old"}]}
      result = JournalHandler.write(state, %{"entry" => "new"})

      assert length(result.journal_entries) == 2
      assert List.last(result.journal_entries)["text"] == "new"
    end

    test "최대 100개까지만 유지한다" do
      existing = for i <- 1..105, do: %{"text" => "old-#{i}"}
      state = %State{id: "c1", journal_entries: existing}

      result = JournalHandler.write(state, %{"entry" => "new"})

      assert length(result.journal_entries) == 100
      assert List.last(result.journal_entries)["text"] == "new"
    end
  end

  describe "JournalHandler.read/2" do
    test "state를 그대로 돌려준다 (no-op)" do
      state = %State{id: "c1", journal_entries: [%{"text" => "기존"}]}
      assert JournalHandler.read(state, %{}) == state
      assert JournalHandler.read(state, %{"filter" => "quest"}) == state
    end
  end

  # ── CombatHandler ────────────────────────────────────────────────────────

  describe "CombatHandler.start/2" do
    test "전투 phase로 전환하고 combat_state를 구성한다" do
      state = %State{
        id: "c1",
        phase: :exploration,
        characters: [%{"name" => "아리아"}, %{"name" => "브론"}]
      }

      result =
        CombatHandler.start(state, %{
          "participants" => ["아리아", "고블린 A"],
          "enemies" => [%{"name" => "고블린 A", "hp_current" => 7, "hp_max" => 7}]
        })

      assert result.phase == :combat
      assert result.combat_state["participants"] == ["아리아", "고블린 A"]
      assert result.combat_state["player_names"] == ["아리아", "브론"]
      assert result.combat_state["round"] == 1
      assert result.combat_state["turn_order"] == []
      assert [%{"name" => "고블린 A"}] = result.combat_state["enemies"]
    end

    test "적이 없으면 enemies 키를 넣지 않는다" do
      state = %State{id: "c1", characters: []}
      result = CombatHandler.start(state, %{"participants" => [], "enemies" => []})
      refute Map.has_key?(result.combat_state, "enemies")
    end
  end

  describe "CombatHandler.finish/2" do
    test "전투를 종료하고 플레이어만 남긴다" do
      state = %State{
        id: "c1",
        phase: :combat,
        characters: [
          %{"name" => "아리아"},
          %{"name" => "고블린 A"}
        ],
        combat_state: %{"player_names" => ["아리아"]}
      }

      result = CombatHandler.finish(state, %{"xp" => 0})

      assert result.phase == :exploration
      assert result.combat_state == nil
      assert [%{"name" => "아리아"}] = result.characters
    end

    test "player_names가 비어 있으면 characters를 보존한다" do
      state = %State{
        id: "c1",
        phase: :combat,
        characters: [%{"name" => "X"}],
        combat_state: %{"player_names" => []}
      }

      result = CombatHandler.finish(state, %{"xp" => 0})

      assert result.characters == [%{"name" => "X"}]
    end
  end
end
