defmodule TrpgMaster.Campaign.Summarizer.Update do
  @moduledoc false

  alias TrpgMaster.Campaign.Persistence
  alias TrpgMaster.Campaign.Summarizer.Text
  require Logger

  def context_summary(state, result, opts \\ []) do
    append_summary_log = Keyword.get(opts, :append_summary_log, &Persistence.append_summary_log/2)

    case result do
      {:ok, new_summary} ->
        maybe_append_previous_summary(state, append_summary_log)
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

  def combat_history_summary(state, result) do
    case result do
      {:ok, summary} ->
        Logger.info("전투 히스토리 요약 갱신 [#{state.id}]")
        %{state | combat_history_summary: summary}

      {:error, reason} ->
        Logger.warning("전투 히스토리 요약 생성 실패 [#{state.id}]: #{inspect(reason)}")
        state
    end
  end

  defp maybe_append_previous_summary(state, append_summary_log) do
    if state.context_summary && Text.meaningful_summary?(state.context_summary) do
      append_summary_log.(state.id, state.context_summary)
    end
  end
end
