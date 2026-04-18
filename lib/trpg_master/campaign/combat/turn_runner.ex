defmodule TrpgMaster.Campaign.Combat.TurnRunner do
  @moduledoc false

  alias TrpgMaster.Campaign.Combat.{Dependencies, Runtime, StatePersistence}
  require Logger

  def handle_action(message, state, opts \\ []) do
    deps = Dependencies.build(opts)
    state = Runtime.start_turn(state, message)

    Logger.info(
      "전투 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — combat_history: #{length(state.combat_history)}개"
    )

    tools = deps.tools.()
    model_opts = opts[:model_opts] || []

    tool_context =
      Keyword.get_lazy(opts, :tool_context, fn -> Dependencies.tool_context(state) end)

    case execute_turn(state, message, :player_turn, tools, model_opts, tool_context, deps) do
      {:ok, player_result, state} ->
        if state.phase != :combat or Runtime.should_end?(state) do
          state = StatePersistence.persist_completed_combat(state, player_result.text, deps)
          {:reply, {:ok, player_result}, state}
        else
          enemy_groups = Runtime.extract_enemy_groups(state)

          handle_enemy_group_turns(
            state,
            [player_result],
            enemy_groups,
            tools,
            model_opts,
            tool_context,
            deps
          )
        end

      {:error, reason, state} ->
        Logger.error("AI 호출 실패 (플레이어 턴) [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  defp handle_enemy_group_turns(state, results, [], tools, model_opts, tool_context, deps) do
    round_trigger = "이번 라운드가 끝났습니다. 라운드를 정리하고 플레이어에게 다음 행동을 물어보세요."

    case execute_turn(
           state,
           round_trigger,
           :round_summary,
           tools,
           model_opts,
           tool_context,
           deps,
           append_history?: true
         ) do
      {:ok, round_result, state} ->
        results = results ++ [round_result]

        if state.phase != :combat or Runtime.should_end?(state) do
          state = StatePersistence.persist_completed_combat(state, round_result.text, deps)
          {:reply, {:ok, results}, state}
        else
          state = StatePersistence.persist_ongoing_combat(state, deps)

          Logger.info(
            "전투 턴 #{state.turn_count} 저장 완료 [#{state.id}] — combat_history: #{length(state.combat_history)}개"
          )

          {:reply, {:ok, results}, state}
        end

      {:error, reason, state} ->
        Logger.error("AI 호출 실패 (라운드 정리) [#{state.id}]: #{inspect(reason)}")
        state = deps.update_combat_history_summary.(state)
        deps.save_async.(state)
        {:reply, {:ok, results}, state}
    end
  end

  defp handle_enemy_group_turns(
         state,
         results,
         [enemy_name | rest],
         tools,
         model_opts,
         tool_context,
         deps
       ) do
    is_last_group = rest == []
    trigger_msg = "이제 #{enemy_name}의 턴입니다. #{enemy_name}의 행동을 서술해주세요."
    combat_phase = {:enemy_turn, enemy_name, is_last_group}

    case execute_turn(
           state,
           trigger_msg,
           combat_phase,
           tools,
           model_opts,
           tool_context,
           deps,
           append_history?: true
         ) do
      {:ok, enemy_result, state} ->
        results = results ++ [enemy_result]

        if state.phase != :combat or Runtime.should_end?(state) do
          state = StatePersistence.persist_completed_combat(state, enemy_result.text, deps)
          {:reply, {:ok, results}, state}
        else
          handle_enemy_group_turns(state, results, rest, tools, model_opts, tool_context, deps)
        end

      {:error, reason, state} ->
        Logger.error("AI 호출 실패 (#{enemy_name} 턴) [#{state.id}]: #{inspect(reason)}")
        deps.save_async.(state)

        if length(results) == 1 do
          {:reply, {:ok, hd(results)}, state}
        else
          {:reply, {:ok, results}, state}
        end
    end
  end

  defp execute_turn(
         state,
         trigger_msg,
         combat_phase,
         tools,
         model_opts,
         tool_context,
         deps,
         opts \\ []
       ) do
    state =
      if Keyword.get(opts, :append_history?, false) do
        Runtime.append_history_entry(state, %{
          "role" => "user",
          "content" => trigger_msg,
          "synthetic" => true
        })
      else
        state
      end

    system_prompt = deps.build_prompt.(state, combat_phase)
    trimmed_history = deps.build_turn_messages.(state, trigger_msg, combat_phase)

    case call_ai_with_context(
           system_prompt,
           trimmed_history,
           tools,
           model_opts,
           tool_context,
           deps.chat
         ) do
      {:ok, result} ->
        {:ok, result, StatePersistence.apply_ai_result(state, result, deps.apply_tools)}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp call_ai_with_context(system_prompt, history, tools, model_opts, tool_context, chat_fun) do
    if tool_context do
      Process.put(:journal_entries, tool_context.journal_entries)
      Process.put(:campaign_characters, tool_context.characters)
    end

    try do
      chat_fun.(system_prompt, history, tools, model_opts)
    after
      if tool_context do
        Process.delete(:journal_entries)
        Process.delete(:campaign_characters)
      end
    end
  end
end
