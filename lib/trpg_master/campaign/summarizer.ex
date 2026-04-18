defmodule TrpgMaster.Campaign.Summarizer do
  @moduledoc """
  AI를 사용한 캠페인 요약 생성.
  세션 요약, 컨텍스트 요약, 전투 히스토리 요약, 전투 종료 요약을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.AI.{Client, Models}
  alias TrpgMaster.Campaign.Persistence
  alias TrpgMaster.Campaign.Summarizer.Prompts

  require Logger

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  세션 종료 시 전체 세션 요약을 생성한다.
  """
  def generate_session_summary(state) do
    haiku_model = summary_model_for(state.ai_model)

    summarize(
      "You are a D&D session scribe.",
      Prompts.session_summary_prompt(state),
      Prompts.recent_combined_history(state),
      haiku_model,
      1024
    )
  end

  @doc """
  탐험 중 슬라이딩 윈도우 밖의 히스토리를 요약한다.
  AI 응답만 요약 대상이며, 이전 요약과 통합한다.
  """
  def generate_context_summary(state) do
    history = state.exploration_history

    ai_messages =
      Enum.filter(history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      :skip
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.context_summary || "(첫 번째 턴 — 이전 요약 없음)"

      summary_messages = [
        %{
          "role" => "user",
          "content" => Prompts.context_summary_prompt(previous, ai_messages)
        }
      ]

      summarize("You are a TRPG session summarizer.", nil, summary_messages, haiku_model, 800)
    end
  end

  @doc """
  전투 중 이전 라운드 히스토리를 요약한다.
  누적 방식으로 이전 요약 + 최근 전투 내용을 통합한다.
  """
  def generate_combat_history_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)
      previous = state.combat_history_summary || "(전투 시작 — 이전 요약 없음)"

      summary_messages = [
        %{
          "role" => "user",
          "content" => Prompts.combat_history_summary_prompt(previous, ai_messages, state)
        }
      ]

      summarize("You are a TRPG combat summarizer.", nil, summary_messages, haiku_model, 600)
    end
  end

  @doc """
  전투 종료 후 전체 전투를 요약한다.
  """
  def generate_post_combat_summary(state) do
    ai_messages =
      Enum.filter(state.combat_history, fn %{"role" => role} -> role == "assistant" end)

    if ai_messages == [] do
      {:ok, nil}
    else
      haiku_model = summary_model_for(state.ai_model)

      summary_messages = [
        %{
          "role" => "user",
          "content" => Prompts.post_combat_summary_prompt(ai_messages, state)
        }
      ]

      summarize("You are a TRPG combat summarizer.", nil, summary_messages, haiku_model, 800)
    end
  end

  @doc """
  컨텍스트 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_context_summary(state) do
    case generate_context_summary(state) do
      {:ok, new_summary} ->
        if state.context_summary && meaningful_summary?(state.context_summary) do
          Persistence.append_summary_log(state.id, state.context_summary)
        end

        Logger.info("컨텍스트 요약 갱신 [#{state.id}]")
        %{state | context_summary: new_summary}

      :skip ->
        Logger.info("컨텍스트 요약 스킵 [#{state.id}] — AI 응답 없음")
        state

      {:error, reason} ->
        Logger.warning("컨텍스트 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  @doc """
  전투 히스토리 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_combat_history_summary(state) do
    case generate_combat_history_summary(state) do
      {:ok, summary} ->
        Logger.info("전투 히스토리 요약 갱신 [#{state.id}]")
        %{state | combat_history_summary: summary}

      {:error, reason} ->
        Logger.warning("전투 히스토리 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  @doc """
  세션 번호를 추정한다 (turn_count 기반).
  """
  def estimate_session_number(state) do
    max(1, div(state.turn_count, 5))
  end

  @doc """
  요약이 의미 있는 내용을 포함하는지 검증한다.
  """
  def meaningful_summary?(text) when is_binary(text) do
    stripped =
      text
      |> String.replace(~r/\d{4}[-\/]\d{1,2}[-\/]\d{1,2}/, "")
      |> String.replace(~r/\d{1,2}:\d{2}(:\d{2})?/, "")
      |> String.replace(~r/[T\-\/:\s.,()]+/, "")
      |> String.replace(~r/첫\s*번째\s*턴/, "")
      |> String.replace("이전 요약 없음", "")
      |> String.trim()

    String.length(stripped) >= 10
  end

  def meaningful_summary?(_), do: false

  def format_combatants_status(state), do: Prompts.format_combatants_status(state)

  # ── Private helpers ────────────────────────────────────────────────────────

  # 공통 AI 요약 호출 패턴
  defp summarize(system_msg, user_prompt, messages, model, max_tokens) do
    messages =
      if user_prompt do
        [%{"role" => "user", "content" => user_prompt} | messages]
      else
        messages
      end

    case Client.chat(system_msg, messages, [], model: model, max_tokens: max_tokens) do
      {:ok, result} -> {:ok, result.text}
      {:error, reason} -> {:error, reason}
    end
  end

  def summary_model_for(nil), do: "claude-haiku-4-5-20251001"

  def summary_model_for(model_id) do
    case Models.provider_for(model_id) do
      :anthropic -> "claude-haiku-4-5-20251001"
      :openai -> "gpt-5.4-mini"
      :gemini -> "gemini-2.5-flash"
      _ -> "claude-haiku-4-5-20251001"
    end
  end
end
