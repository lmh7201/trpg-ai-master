defmodule TrpgMaster.Campaign.ToolHandler do
  @moduledoc """
  AI 도구 실행 결과를 캠페인 상태에 반영하는 dispatcher.

  각 도구 타입의 실제 상태 변경 로직은 전담 handler 모듈에서 담당한다:

  - `update_character`, `level_up` → `CharacterUpdater`
  - `register_npc` → `NpcHandler`
  - `update_quest` → `QuestHandler`
  - `set_location` → `LocationHandler`
  - `start_combat`, `end_combat` → `CombatHandler`
  - `write_journal`, `read_journal` → `JournalHandler`

  이 모듈은 dispatch만 담당하고, 각 handler는 독립적으로 테스트한다.
  """

  alias TrpgMaster.Campaign.ToolHandler.{
    CharacterUpdater,
    CombatHandler,
    JournalHandler,
    LocationHandler,
    NpcHandler,
    QuestHandler
  }

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  도구 결과 리스트를 순회하며 캠페인 상태에 반영한다.
  """
  def apply_all(state, tool_results) do
    Enum.reduce(tool_results, state, fn result, acc ->
      apply_one(acc, result)
    end)
  end

  # ── Dispatch table ──────────────────────────────────────────────────────────

  def apply_one(state, %{tool: "update_character", input: input}),
    do: CharacterUpdater.update_character(state, input)

  def apply_one(state, %{tool: "level_up", input: input}),
    do: CharacterUpdater.level_up(state, input)

  def apply_one(state, %{tool: "register_npc", input: input}),
    do: NpcHandler.apply(state, input)

  def apply_one(state, %{tool: "update_quest", input: input}),
    do: QuestHandler.apply(state, input)

  def apply_one(state, %{tool: "set_location", input: input}),
    do: LocationHandler.apply(state, input)

  def apply_one(state, %{tool: "start_combat", input: input}),
    do: CombatHandler.start(state, input)

  def apply_one(state, %{tool: "end_combat", input: input}),
    do: CombatHandler.finish(state, input)

  def apply_one(state, %{tool: "write_journal", input: input}),
    do: JournalHandler.write(state, input)

  def apply_one(state, %{tool: "read_journal", input: input}),
    do: JournalHandler.read(state, input)

  def apply_one(state, result) do
    Logger.debug("알 수 없는 도구 결과 무시: #{inspect(result.tool)}")
    state
  end
end
