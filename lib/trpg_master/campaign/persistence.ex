defmodule TrpgMaster.Campaign.Persistence do
  @moduledoc """
  캠페인 상태를 파일 시스템에 저장하고 로드한다.
  """

  alias TrpgMaster.Campaign.Persistence.{Files, History}
  alias TrpgMaster.Campaign.State

  require Logger

  @schema_version 2

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  캠페인 상태 전체를 파일에 저장한다.
  """
  def save(%State{} = state) do
    with :ok <- Files.save_state(state, @schema_version) do
      :ok
    else
      {:error, reason} ->
        Logger.error("캠페인 저장 실패 [#{state.id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  비동기로 캠페인 상태를 저장한다 (응답 지연 방지).

  `TrpgMaster.TaskSupervisor` 아래에서 실행하므로 Task가 크래시해도
  상위 supervisor가 로그를 남기고 상태가 예측 가능하게 유지된다.
  """
  def save_async(%State{} = state) do
    Task.Supervisor.start_child(TrpgMaster.TaskSupervisor, fn ->
      try do
        case save(state) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.error("[Persistence] 캠페인 #{state.id} 저장 실패: #{inspect(reason)}")
        end
      rescue
        e ->
          Logger.error("[Persistence] 캠페인 #{state.id} 저장 중 예외: #{Exception.message(e)}")
      end
    end)
  end

  @doc """
  캠페인을 파일에서 로드한다.
  """
  def load(campaign_id) do
    with {:ok, loaded} <- Files.load_state(campaign_id),
         :ok <- check_schema_version(loaded.summary) do
      state =
        State.from_summary(loaded.summary)
        |> Map.put(:characters, loaded.characters)
        |> Map.put(:npcs, loaded.npcs)
        |> Map.put(:exploration_history, loaded.exploration_history)
        |> Map.put(:combat_history, loaded.combat_history)
        |> Map.put(:journal_entries, loaded.journal_entries)
        |> Map.put(:context_summary, loaded.context_summary)

      {:ok, state}
    end
  end

  @doc """
  저장된 캠페인 목록을 반환한다 (최근 업데이트 순).
  """
  def list_campaigns, do: Files.list_campaigns()

  @doc """
  히스토리 화면에 필요한 캠페인 메타데이터와 로그를 함께 로드한다.
  """
  def load_campaign_history(campaign_id), do: History.load_campaign_history(campaign_id)

  @doc """
  세션 로그를 campaign-log.md에 추가한다.
  """
  def append_session_log(%State{} = state, session_number, summary_text),
    do: History.append_session_log(state, session_number, summary_text)

  @doc """
  campaign-log.md 파일에서 세션 요약 목록을 로드한다.
  반환: {:ok, [String.t()]} — 각 항목은 세션 하나의 마크다운 텍스트
  """
  def load_session_log(campaign_id), do: History.load_session_log(campaign_id)

  @doc """
  AI 컨텍스트 요약 로그를 summary_log.jsonl에서 로드한다.
  """
  def load_summary_log(campaign_id), do: History.load_summary_log(campaign_id)

  @doc """
  컨텍스트 요약 로그를 summary_log.jsonl에 추가한다.
  """
  def append_summary_log(campaign_id, summary_text),
    do: History.append_summary_log(campaign_id, summary_text)

  @doc """
  캠페인 데이터를 삭제한다.
  """
  def delete(campaign_id), do: Files.delete_campaign(campaign_id)

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp check_schema_version(summary) do
    version = summary["schema_version"] || 0

    if version < @schema_version do
      Logger.warning("[Persistence] 구버전 세이브 파일 (v#{version}). 현재 v#{@schema_version}.")
    end

    :ok
  end
end
