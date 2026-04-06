defmodule TrpgMaster.Campaign.Combat do
  @moduledoc """
  전투 흐름 관리.
  플레이어 턴, 적 그룹별 턴, 라운드 정리, 전투 종료 판단을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.Campaign.{Persistence, ToolHandler, Summarizer}
  alias TrpgMaster.AI.{Client, PromptBuilder, Tools}

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  전투 모드에서 플레이어 액션을 처리한다.
  `{:reply, reply_value, new_state}` 튜플을 반환한다.
  """
  def handle_action(message, state, opts \\ []) do
    # 1) 현재 라운드 시작 인덱스를 기록한 뒤 플레이어 메시지를 combat_history에 추가
    round_start_index = length(state.combat_history)
    state = %{state |
      current_round_start_index: round_start_index,
      combat_history: state.combat_history ++ [%{"role" => "user", "content" => message}]
    }

    Logger.info(
      "전투 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — combat_history: #{length(state.combat_history)}개"
    )

    # 2) 플레이어 턴 API 호출
    system_prompt = PromptBuilder.build(state, combat_phase: :player_turn)
    tools = Tools.definitions(:combat) ++ Tools.state_tool_definitions()
    trimmed_history = PromptBuilder.build_turn_messages(state, message, combat_phase: :player_turn)
    model_opts = opts[:model_opts] || []
    tool_context = opts[:tool_context]

    player_result = call_ai_with_context(system_prompt, trimmed_history, tools, model_opts, tool_context)

    case player_result do
      {:ok, player_result} ->
        state_before = state
        state = ToolHandler.apply_all(state, player_result.tool_results)
        log_npc_changes(state, state_before)

        # 플레이어 턴 AI 응답을 combat_history에 추가
        state = %{
          state
          | combat_history:
              state.combat_history ++ [%{"role" => "assistant", "content" => player_result.text}]
        }

        # end_combat 호출 또는 전멸 감지 시 전투 종료
        if state.phase != :combat or should_end?(state) do
          state = force_end_if_needed(state)
          state = finalize(state, player_result.text)
          state = Summarizer.update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, player_result}, state}
        else
          # 3) 적 그룹별 순차 API 호출
          enemy_groups = extract_enemy_groups(state)
          handle_enemy_group_turns(state, [player_result], enemy_groups, tools, model_opts, tool_context)
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
  def should_end?(state) do
    player_names = get_in(state.combat_state, ["player_names"]) || []
    enemies = get_in(state.combat_state, ["enemies"]) || []

    all_players_dead?(state.characters, player_names) or
      all_enemies_dead?(enemies)
  end

  @doc """
  전멸 감지 시 강제로 전투를 종료한다.
  """
  def force_end_if_needed(%{phase: :combat} = state) do
    Logger.info("전멸 감지로 전투 자동 종료 [#{state.id}]")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  def force_end_if_needed(state), do: state

  @doc """
  전투 종료 처리: post_combat_summary 생성, combat_history 초기화.
  """
  def finalize(state, last_response_text) do
    Logger.info("전투 종료 처리 [#{state.id}] — combat_history: #{length(state.combat_history)}개")

    # 전투 마무리 서술을 exploration_history에 추가
    transition_text = "[전투 종료] " <> last_response_text
    state = %{
      state
      | exploration_history:
          state.exploration_history ++ [%{"role" => "assistant", "content" => transition_text}]
    }

    # post_combat_summary 생성
    state =
      case Summarizer.generate_post_combat_summary(state) do
        {:ok, summary} ->
          Logger.info("전투 종료 요약 생성 완료 [#{state.id}]")
          %{state | post_combat_summary: summary}

        {:error, reason} ->
          Logger.warning("전투 종료 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
          state
      end

    # combat_history, combat_history_summary 초기화
    %{state | combat_history: [], combat_history_summary: nil}
  end

  # ── Private: Enemy Group Turns ─────────────────────────────────────────────

  # 모든 적 그룹 처리 완료 → 라운드 정리 API 호출
  defp handle_enemy_group_turns(state, results, [], tools, model_opts, tool_context) do
    round_trigger = "이번 라운드가 끝났습니다. 라운드를 정리하고 플레이어에게 다음 행동을 물어보세요."
    state = %{state | combat_history: state.combat_history ++ [%{"role" => "user", "content" => round_trigger, "synthetic" => true}]}

    system_prompt = PromptBuilder.build(state, combat_phase: :round_summary)
    trimmed_history = PromptBuilder.build_turn_messages(state, round_trigger)

    round_result = call_ai_with_context(system_prompt, trimmed_history, tools, model_opts, tool_context)

    case round_result do
      {:ok, round_result} ->
        state_before = state
        state = ToolHandler.apply_all(state, round_result.tool_results)
        log_npc_changes(state, state_before)

        state = %{state | combat_history: state.combat_history ++ [%{"role" => "assistant", "content" => round_result.text}]}

        results = results ++ [round_result]

        # 전투 종료 체크
        if state.phase != :combat or should_end?(state) do
          state = force_end_if_needed(state)
          state = finalize(state, round_result.text)
          state = Summarizer.update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, results}, state}
        else
          state = Summarizer.update_combat_history_summary(state)
          state = Summarizer.update_context_summary(state)
          Persistence.save_async(state)

          Logger.info(
            "전투 턴 #{state.turn_count} 저장 완료 [#{state.id}] — combat_history: #{length(state.combat_history)}개"
          )

          {:reply, {:ok, results}, state}
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (라운드 정리) [#{state.id}]: #{inspect(reason)}")
        state = Summarizer.update_combat_history_summary(state)
        Persistence.save_async(state)
        {:reply, {:ok, results}, state}
    end
  end

  defp handle_enemy_group_turns(state, results, [enemy_name | rest], tools, model_opts, tool_context) do
    is_last_group = rest == []
    trigger_msg = "이제 #{enemy_name}의 턴입니다. #{enemy_name}의 행동을 서술해주세요."
    combat_phase = {:enemy_turn, enemy_name, is_last_group}

    state = %{state | combat_history: state.combat_history ++ [%{"role" => "user", "content" => trigger_msg, "synthetic" => true}]}

    system_prompt = PromptBuilder.build(state, combat_phase: combat_phase)
    trimmed_history = PromptBuilder.build_turn_messages(state, trigger_msg, combat_phase: combat_phase)

    enemy_result = call_ai_with_context(system_prompt, trimmed_history, tools, model_opts, tool_context)

    case enemy_result do
      {:ok, enemy_result} ->
        state_before = state
        state = ToolHandler.apply_all(state, enemy_result.tool_results)
        log_npc_changes(state, state_before)

        state = %{
          state
          | combat_history:
              state.combat_history ++ [%{"role" => "assistant", "content" => enemy_result.text}]
        }

        results = results ++ [enemy_result]

        # end_combat 호출 또는 전멸 감지 시 전투 종료, 나머지 적 그룹 스킵
        if state.phase != :combat or should_end?(state) do
          state = force_end_if_needed(state)
          state = finalize(state, enemy_result.text)
          state = Summarizer.update_context_summary(state)
          Persistence.save_async(state)
          {:reply, {:ok, results}, state}
        else
          handle_enemy_group_turns(state, results, rest, tools, model_opts, tool_context)
        end

      {:error, reason} ->
        Logger.error("AI 호출 실패 (#{enemy_name} 턴) [#{state.id}]: #{inspect(reason)}")
        Persistence.save_async(state)

        if length(results) == 1 do
          {:reply, {:ok, hd(results)}, state}
        else
          {:reply, {:ok, results}, state}
        end
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp extract_enemy_groups(state) do
    case get_in(state.combat_state, ["enemies"]) do
      enemies when is_list(enemies) and enemies != [] ->
        enemies
        |> Enum.reject(fn e ->
          hp = e["hp_current"]
          is_number(hp) and hp <= 0
        end)
        |> Enum.map(fn e -> e["name"] end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      _ ->
        ["적"]
    end
  end

  defp all_players_dead?(characters, player_names) when player_names != [] do
    players = Enum.filter(characters, fn c -> c["name"] in player_names end)

    players != [] and
      Enum.all?(players, fn c ->
        hp = c["hp_current"]
        is_number(hp) and hp <= 0
      end)
  end

  defp all_players_dead?(_, _), do: false

  defp all_enemies_dead?(enemies) when is_list(enemies) and enemies != [] do
    Enum.all?(enemies, fn e ->
      hp = e["hp_current"]
      is_number(hp) and hp <= 0
    end)
  end

  defp all_enemies_dead?(_), do: false

  defp call_ai_with_context(system_prompt, history, tools, model_opts, tool_context) do
    if tool_context do
      Process.put(:journal_entries, tool_context.journal_entries)
      Process.put(:campaign_characters, tool_context.characters)
    end

    try do
      Client.chat(system_prompt, history, tools, model_opts)
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
