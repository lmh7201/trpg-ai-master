defmodule TrpgMaster.Campaign.Combat.StatePersistence do
  @moduledoc false

  alias TrpgMaster.Campaign.Combat.Runtime
  require Logger

  def apply_ai_result(state, result, apply_tools_fun) do
    state_before = state
    state = apply_tools_fun.(state, result.tool_results)
    log_npc_changes(state, state_before)
    Runtime.append_history_entry(state, %{"role" => "assistant", "content" => result.text})
  end

  def persist_completed_combat(state, last_response_text, deps) do
    state = Runtime.force_end_if_needed(state)
    state = Runtime.finalize(state, last_response_text, deps.generate_post_combat_summary)
    state = deps.update_context_summary.(state)
    deps.save_async.(state)
    state
  end

  def persist_ongoing_combat(state, deps) do
    state = deps.update_combat_history_summary.(state)
    state = deps.update_context_summary.(state)
    deps.save_async.(state)
    state
  end

  defp log_npc_changes(state, state_before) do
    if map_size(state.npcs) != map_size(state_before.npcs) do
      Logger.info(
        "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개"
      )
    end
  end
end
