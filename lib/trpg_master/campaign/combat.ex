defmodule TrpgMaster.Campaign.Combat do
  @moduledoc """
  전투 흐름 관리.
  플레이어 턴, 적 그룹별 턴, 라운드 정리, 전투 종료 판단을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.AI.{Client, PromptBuilder, Tools}
  alias TrpgMaster.Campaign.{Persistence, ToolHandler, Summarizer}
  alias TrpgMaster.Campaign.Combat.Runtime

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  전투 모드에서 플레이어 액션을 처리한다.
  `{:reply, reply_value, new_state}` 튜플을 반환한다.
  """
  def handle_action(message, state, opts \\ []) do
    deps = dependencies(opts)
    state = Runtime.start_turn(state, message)

    Logger.info(
      "전투 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — combat_history: #{length(state.combat_history)}개"
    )

    system_prompt = deps.build_prompt.(state, :player_turn)
    tools = deps.tools.()
    trimmed_history = deps.build_turn_messages.(state, message, :player_turn)
    model_opts = opts[:model_opts] || []
    tool_context = Keyword.get_lazy(opts, :tool_context, fn -> tool_context(state) end)

    player_result =
      call_ai_with_context(
        system_prompt,
        trimmed_history,
        tools,
        model_opts,
        tool_context,
        deps.chat
      )

    case player_result do
      {:ok, player_result} ->
        state = apply_ai_result(state, player_result, deps.apply_tools)

        if state.phase != :combat or should_end?(state) do
          state = persist_completed_combat(state, player_result.text, deps)
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

      {:error, reason} ->
        Logger.error("AI 호출 실패 (플레이어 턴) [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # ── Combat State Checks ────────────────────────────────────────────────────

  @doc """
  플레이어 전멸 또는 적 전멸 시 전투 자동 종료 판단.
  """
  def should_end?(state), do: Runtime.should_end?(state)

  @doc """
  전멸 감지 시 강제로 전투를 종료한다.
  """
  def force_end_if_needed(state), do: Runtime.force_end_if_needed(state)

  @doc """
  전투 종료 처리: post_combat_summary 생성, combat_history 초기화.
  """
  def finalize(state, last_response_text), do: Runtime.finalize(state, last_response_text)

  # ── Private: Enemy Group Turns ─────────────────────────────────────────────

  # 모든 적 그룹 처리 완료 → 라운드 정리 API 호출
  defp handle_enemy_group_turns(state, results, [], tools, model_opts, tool_context, deps) do
    round_trigger = "이번 라운드가 끝났습니다. 라운드를 정리하고 플레이어에게 다음 행동을 물어보세요."

    state =
      Runtime.append_history_entry(state, %{
        "role" => "user",
        "content" => round_trigger,
        "synthetic" => true
      })

    system_prompt = deps.build_prompt.(state, :round_summary)
    trimmed_history = deps.build_turn_messages.(state, round_trigger, :round_summary)

    round_result =
      call_ai_with_context(
        system_prompt,
        trimmed_history,
        tools,
        model_opts,
        tool_context,
        deps.chat
      )

    case round_result do
      {:ok, round_result} ->
        state = apply_ai_result(state, round_result, deps.apply_tools)
        results = results ++ [round_result]

        if state.phase != :combat or should_end?(state) do
          state = persist_completed_combat(state, round_result.text, deps)
          {:reply, {:ok, results}, state}
        else
          state = persist_ongoing_combat(state, deps)

          Logger.info(
            "전투 턴 #{state.turn_count} 저장 완료 [#{state.id}] — combat_history: #{length(state.combat_history)}개"
          )

          {:reply, {:ok, results}, state}
        end

      {:error, reason} ->
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

    state =
      Runtime.append_history_entry(state, %{
        "role" => "user",
        "content" => trigger_msg,
        "synthetic" => true
      })

    system_prompt = deps.build_prompt.(state, combat_phase)
    trimmed_history = deps.build_turn_messages.(state, trigger_msg, combat_phase)

    enemy_result =
      call_ai_with_context(
        system_prompt,
        trimmed_history,
        tools,
        model_opts,
        tool_context,
        deps.chat
      )

    case enemy_result do
      {:ok, enemy_result} ->
        state = apply_ai_result(state, enemy_result, deps.apply_tools)
        results = results ++ [enemy_result]

        if state.phase != :combat or should_end?(state) do
          state = persist_completed_combat(state, enemy_result.text, deps)
          {:reply, {:ok, results}, state}
        else
          handle_enemy_group_turns(state, results, rest, tools, model_opts, tool_context, deps)
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (#{enemy_name} 턴) [#{state.id}]: #{inspect(reason)}")
        deps.save_async.(state)

        if length(results) == 1 do
          {:reply, {:ok, hd(results)}, state}
        else
          {:reply, {:ok, results}, state}
        end
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp dependencies(opts) do
    %{
      build_prompt: Keyword.get(opts, :build_prompt, &default_build_prompt/2),
      build_turn_messages:
        Keyword.get(opts, :build_turn_messages, &default_build_turn_messages/3),
      tools: Keyword.get(opts, :tools, &default_tools/0),
      chat: Keyword.get(opts, :chat, &Client.chat/4),
      apply_tools: Keyword.get(opts, :apply_tools, &ToolHandler.apply_all/2),
      update_context_summary:
        Keyword.get(opts, :update_context_summary, &Summarizer.update_context_summary/1),
      update_combat_history_summary:
        Keyword.get(
          opts,
          :update_combat_history_summary,
          &Summarizer.update_combat_history_summary/1
        ),
      generate_post_combat_summary:
        Keyword.get(
          opts,
          :generate_post_combat_summary,
          &Summarizer.generate_post_combat_summary/1
        ),
      save_async: Keyword.get(opts, :save_async, &Persistence.save_async/1)
    }
  end

  defp default_build_prompt(state, combat_phase) do
    PromptBuilder.build(state, combat_phase: combat_phase)
  end

  defp default_build_turn_messages(state, message, combat_phase) do
    PromptBuilder.build_turn_messages(state, message, combat_phase: combat_phase)
  end

  defp default_tools do
    Tools.definitions(:combat) ++ Tools.state_tool_definitions()
  end

  defp tool_context(state) do
    %{journal_entries: state.journal_entries, characters: state.characters}
  end

  defp apply_ai_result(state, result, apply_tools_fun) do
    state_before = state
    state = apply_tools_fun.(state, result.tool_results)
    log_npc_changes(state, state_before)
    Runtime.append_history_entry(state, %{"role" => "assistant", "content" => result.text})
  end

  defp persist_completed_combat(state, last_response_text, deps) do
    state = Runtime.force_end_if_needed(state)
    state = Runtime.finalize(state, last_response_text, deps.generate_post_combat_summary)
    state = deps.update_context_summary.(state)
    deps.save_async.(state)
    state
  end

  defp persist_ongoing_combat(state, deps) do
    state = deps.update_combat_history_summary.(state)
    state = deps.update_context_summary.(state)
    deps.save_async.(state)
    state
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

  defp log_npc_changes(state, state_before) do
    if map_size(state.npcs) != map_size(state_before.npcs) do
      Logger.info(
        "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개"
      )
    end
  end
end
