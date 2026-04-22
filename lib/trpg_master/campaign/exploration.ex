defmodule TrpgMaster.Campaign.Exploration do
  @moduledoc """
  탐험 모드 액션 처리.
  프롬프트 생성, AI 호출, 도구 반영, 컨텍스트 요약 갱신을 담당한다.
  """

  alias TrpgMaster.AI.{Client, PromptBuilder, Tools, ToolContext}
  alias TrpgMaster.Campaign.{Persistence, Summarizer, ToolHandler}

  require Logger

  @doc """
  탐험 모드에서 플레이어 액션을 처리한다.
  `{:reply, reply_value, new_state}` 튜플을 반환한다.
  """
  def handle_action(message, state, opts \\ []) do
    deps = dependencies(opts)
    history = state.exploration_history ++ [%{"role" => "user", "content" => message}]
    state = %{state | exploration_history: history}

    Logger.info("탐험 액션 처리 시작 [#{state.id}] 턴 #{state.turn_count} — 히스토리: #{length(history)}개")

    system_prompt = deps.build_prompt.(state)
    tools = deps.tools_for_phase.(state.phase)
    trimmed_history = deps.build_turn_messages.(state, message)
    model_opts = Keyword.get(opts, :model_opts, [])
    tool_context = Keyword.get_lazy(opts, :tool_context, fn -> tool_context(state) end)

    result =
      call_ai_with_context(
        system_prompt,
        trimmed_history,
        tools,
        model_opts,
        tool_context,
        deps.chat
      )

    case result do
      {:ok, result} ->
        state_before = state
        state = deps.apply_tools.(state, result.tool_results)
        log_npc_changes(state, state_before)

        state = %{
          state
          | exploration_history:
              state.exploration_history ++ [%{"role" => "assistant", "content" => result.text}]
        }

        state = consume_post_combat_summary(state)
        state = deps.update_context_summary.(state)
        deps.save_async.(state)

        Logger.info(
          "턴 #{state.turn_count} 저장 완료 [#{state.id}] — npcs: #{map_size(state.npcs)}개, exploration: #{length(state.exploration_history)}개"
        )

        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.error("AI 호출 실패 [#{state.id}]: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  defp dependencies(opts) do
    %{
      build_prompt: Keyword.get(opts, :build_prompt, &PromptBuilder.build/1),
      build_turn_messages:
        Keyword.get(opts, :build_turn_messages, &PromptBuilder.build_turn_messages/2),
      tools_for_phase:
        Keyword.get(opts, :tools_for_phase, fn phase ->
          Tools.definitions(phase) ++ Tools.state_tool_definitions()
        end),
      chat: Keyword.get(opts, :chat, &Client.chat/4),
      apply_tools: Keyword.get(opts, :apply_tools, &ToolHandler.apply_all/2),
      update_context_summary:
        Keyword.get(opts, :update_context_summary, &Summarizer.update_context_summary/1),
      save_async: Keyword.get(opts, :save_async, &Persistence.save_async/1)
    }
  end

  defp tool_context(state) do
    %{journal_entries: state.journal_entries, characters: state.characters}
  end

  defp call_ai_with_context(system_prompt, history, tools, model_opts, tool_context, chat_fun) do
    ToolContext.with_context(tool_context, fn ->
      chat_fun.(system_prompt, history, tools, model_opts)
    end)
  end

  defp consume_post_combat_summary(%{post_combat_summary: nil} = state), do: state
  defp consume_post_combat_summary(state), do: %{state | post_combat_summary: nil}

  defp log_npc_changes(state, state_before) do
    if map_size(state.npcs) != map_size(state_before.npcs) do
      Logger.info(
        "NPC 상태 변경 [#{state.id}]: #{map_size(state_before.npcs)}개 → #{map_size(state.npcs)}개"
      )
    end
  end
end
