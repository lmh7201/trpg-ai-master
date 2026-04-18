defmodule TrpgMaster.Campaign.ToolHandler do
  @moduledoc """
  AI 도구 실행 결과를 캠페인 상태에 반영한다.
  Campaign.Server에서 분리된 순수 상태 변환 모듈.
  """

  alias TrpgMaster.Campaign.ToolHandler.CharacterUpdater

  require Logger

  @max_journal_entries 100

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  도구 결과 리스트를 순회하며 캠페인 상태에 반영한다.
  """
  def apply_all(state, tool_results) do
    Enum.reduce(tool_results, state, fn result, acc ->
      apply_one(acc, result)
    end)
  end

  # ── 개별 도구 핸들러 ────────────────────────────────────────────────────────

  def apply_one(state, %{tool: "update_character", input: input}) do
    CharacterUpdater.update_character(state, input)
  end

  def apply_one(state, %{tool: "register_npc", input: input}) do
    name = input["name"]
    Logger.info("NPC 등록: #{name}")

    npc_data =
      Map.merge(
        Map.get(state.npcs, name, %{}),
        input |> Map.drop(["name"]) |> Map.reject(fn {_k, v} -> is_nil(v) end)
      )
      |> Map.put("name", name)

    %{state | npcs: Map.put(state.npcs, name, npc_data)}
  end

  def apply_one(state, %{tool: "update_quest", input: input}) do
    quest_name = input["quest_name"]

    quests =
      case Enum.find_index(state.active_quests, &(&1["name"] == quest_name)) do
        nil ->
          state.active_quests ++
            [
              %{
                "name" => quest_name,
                "status" => input["status"] || "발견",
                "description" => input["description"],
                "notes" => input["notes"]
              }
            ]

        idx ->
          List.update_at(state.active_quests, idx, fn quest ->
            quest
            |> maybe_put("status", input["status"])
            |> maybe_put("description", input["description"])
            |> maybe_put("notes", input["notes"])
          end)
      end

    %{state | active_quests: quests}
  end

  def apply_one(state, %{tool: "set_location", input: input}) do
    Logger.info("위치 변경: #{state.current_location} → #{input["location_name"]}")
    %{state | current_location: input["location_name"]}
  end

  def apply_one(state, %{tool: "start_combat", input: input}) do
    if state.combat_state do
      Logger.warning("[Campaign #{state.id}] 기존 전투가 진행 중인데 새 전투가 시작됨. 기존 전투를 덮어씁니다.")
    end

    participants = input["participants"] || []
    enemies = input["enemies"]
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    player_names = Enum.map(state.characters, fn c -> c["name"] end)

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => [],
      "player_names" => player_names
    }

    combat =
      if is_list(enemies) && enemies != [] do
        Map.put(combat, "enemies", enemies)
      else
        combat
      end

    %{state | phase: :combat, combat_state: combat}
  end

  def apply_one(state, %{tool: "end_combat", input: input}) do
    Logger.info("전투 종료")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    xp_gained = input["xp"] || 0

    characters =
      if xp_gained > 0 do
        Enum.map(characters, fn char -> CharacterUpdater.apply_xp_gain(char, xp_gained) end)
      else
        characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  def apply_one(state, %{tool: "level_up", input: input}) do
    CharacterUpdater.level_up(state, input)
  end

  def apply_one(state, %{tool: "write_journal", input: input}) do
    entry_text = input["entry"]
    category = input["category"] || "note"

    entry = %{
      "text" => entry_text,
      "category" => category,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("저널 기록 [#{state.id}] [#{category}]: #{String.slice(entry_text, 0, 50)}...")

    entries = (state.journal_entries ++ [entry]) |> Enum.take(-@max_journal_entries)
    %{state | journal_entries: entries}
  end

  def apply_one(state, %{tool: "read_journal", input: _input}) do
    # read_journal은 Tools.execute에서 프로세스 딕셔너리로 처리하므로 상태 변경 없음
    state
  end

  def apply_one(state, result) do
    Logger.debug("알 수 없는 도구 결과 무시: #{inspect(result.tool)}")
    state
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
