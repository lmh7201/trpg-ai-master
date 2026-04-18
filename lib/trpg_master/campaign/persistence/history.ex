defmodule TrpgMaster.Campaign.Persistence.History do
  @moduledoc false

  alias TrpgMaster.Campaign.Persistence.Files
  alias TrpgMaster.Campaign.State

  require Logger

  def load_campaign_history(campaign_id) do
    with {:ok, summary} <- Files.read_json(Files.summary_path(campaign_id)),
         {:ok, sessions} <- load_session_log(campaign_id),
         {:ok, summary_logs} <- load_summary_log(campaign_id) do
      {:ok,
       %{
         name: summary["name"] || campaign_id,
         sessions: sessions,
         summary_logs: summary_logs
       }}
    else
      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("캠페인 히스토리 로드 실패 [#{campaign_id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def append_session_log(%State{} = state, session_number, summary_text) do
    dir = Files.campaign_dir(state.id)
    log_path = Path.join(dir, "campaign-log.md")
    date_str = Date.utc_today() |> Date.to_iso8601()

    entry = """

    ---

    # 세션 #{session_number} — #{date_str}

    #{summary_text}

    #{format_party_section(state)}
    """

    case File.write(log_path, entry, [:append]) do
      :ok ->
        Logger.info("세션 로그 추가 완료 [#{state.id}] 세션 #{session_number}")
        :ok

      {:error, reason} ->
        Logger.error("세션 로그 저장 실패 [#{state.id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def load_session_log(campaign_id) do
    path = Path.join(Files.campaign_dir(campaign_id), "campaign-log.md")

    case File.read(path) do
      {:ok, content} ->
        sessions =
          content
          |> String.split(~r/\n---\n/, trim: true)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, sessions}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def load_summary_log(campaign_id) do
    path = Path.join(Files.campaign_dir(campaign_id), "summary_log.jsonl")

    case File.read(path) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case Jason.decode(line) do
              {:ok, entry} -> entry
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        {:ok, entries}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def append_summary_log(campaign_id, summary_text) do
    dir = Files.campaign_dir(campaign_id)
    log_path = Path.join(dir, "summary_log.jsonl")

    with :ok <- File.mkdir_p(dir),
         entry <- build_summary_log_entry(summary_text),
         :ok <- File.write(log_path, entry <> "\n", [:append]) do
      :ok
    else
      {:error, reason} ->
        Logger.error("요약 로그 저장 실패 [#{campaign_id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_summary_log_entry(summary_text) do
    Jason.encode!(%{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => summary_text
    })
  end

  defp format_party_section(state) do
    chars =
      state.characters
      |> Enum.map(fn character ->
        hp =
          if character["hp_current"] && character["hp_max"] do
            " HP #{character["hp_current"]}/#{character["hp_max"]}"
          else
            ""
          end

        "- #{character["name"]}#{hp}"
      end)
      |> Enum.join("\n")

    quests =
      state.active_quests
      |> Enum.map(fn quest -> "- #{quest["name"]} [#{quest["status"] || "진행중"}]" end)
      |> Enum.join("\n")

    location = state.current_location || "미정"

    """
    ## 파티 현황 (자동 기록)
    - 위치: #{location}
    #{if chars != "", do: chars, else: "- (캐릭터 없음)"}

    ## 활성 퀘스트
    #{if quests != "", do: quests, else: "- (없음)"}
    """
  end
end
