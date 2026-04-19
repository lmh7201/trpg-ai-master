defmodule TrpgMaster.Campaign.Summarizer do
  @moduledoc """
  AI를 사용한 캠페인 요약 생성.
  세션 요약, 컨텍스트 요약, 전투 히스토리 요약, 전투 종료 요약을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.AI.Client
  alias TrpgMaster.Campaign.Summarizer.{ModelPolicy, Prompts, Request, Text, Update}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  세션 종료 시 전체 세션 요약을 생성한다.
  """
  def generate_session_summary(state), do: state |> Request.session() |> summarize()

  @doc """
  탐험 중 슬라이딩 윈도우 밖의 히스토리를 요약한다.
  AI 응답만 요약 대상이며, 이전 요약과 통합한다.
  """
  def generate_context_summary(state) do
    case Request.context(state) do
      :skip -> :skip
      request -> summarize(request)
    end
  end

  @doc """
  전투 중 이전 라운드 히스토리를 요약한다.
  누적 방식으로 이전 요약 + 최근 전투 내용을 통합한다.
  """
  def generate_combat_history_summary(state) do
    case Request.combat_history(state) do
      nil -> {:ok, nil}
      request -> summarize(request)
    end
  end

  @doc """
  전투 종료 후 전체 전투를 요약한다.
  """
  def generate_post_combat_summary(state) do
    case Request.post_combat(state) do
      nil -> {:ok, nil}
      request -> summarize(request)
    end
  end

  @doc """
  컨텍스트 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_context_summary(state),
    do: state |> generate_context_summary() |> then(&Update.context_summary(state, &1))

  @doc """
  전투 히스토리 요약을 갱신한다. state를 받아 갱신된 state를 반환.
  """
  def update_combat_history_summary(state),
    do:
      state
      |> generate_combat_history_summary()
      |> then(&Update.combat_history_summary(state, &1))

  @doc """
  세션 번호를 추정한다 (turn_count 기반).
  """
  def estimate_session_number(state) do
    max(1, div(state.turn_count, 5))
  end

  @doc """
  요약이 의미 있는 내용을 포함하는지 검증한다.
  """
  defdelegate meaningful_summary?(text), to: Text

  def format_combatants_status(state), do: Prompts.format_combatants_status(state)
  defdelegate summary_model_for(model_id), to: ModelPolicy

  # ── Private helpers ────────────────────────────────────────────────────────

  defp summarize(request) do
    case Client.chat(request.system, request.messages, [],
           model: request.model,
           max_tokens: request.max_tokens
         ) do
      {:ok, result} -> {:ok, result.text}
      {:error, reason} -> {:error, reason}
    end
  end
end
