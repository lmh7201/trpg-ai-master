defmodule TrpgMaster.Campaign.Persistence do
  @moduledoc """
  캠페인 상태를 파일 시스템에 저장하고 로드한다.
  """

  alias TrpgMaster.Campaign.State

  require Logger

  @schema_version 2

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  캠페인 상태 전체를 파일에 저장한다.
  """
  def save(%State{} = state) do
    dir = campaign_dir(state.id)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.mkdir_p(Path.join(dir, "characters")),
         :ok <- File.mkdir_p(Path.join(dir, "npcs")),
         summary <- State.to_summary(state) |> Map.put("schema_version", @schema_version),
         :ok <- write_json(Path.join(dir, "campaign-summary.json"), summary),
         :ok <- save_characters(dir, state.characters),
         :ok <- save_npcs(dir, state.npcs),
         :ok <- write_json(Path.join(dir, "exploration_history.json"), state.exploration_history),
         :ok <- write_json(Path.join(dir, "combat_history.json"), state.combat_history),
         :ok <- write_json(Path.join(dir, "journal.json"), state.journal_entries),
         :ok <- save_context_summary(dir, state.context_summary) do
      :ok
    else
      {:error, reason} ->
        Logger.error("캠페인 저장 실패 [#{state.id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  비동기로 캠페인 상태를 저장한다 (응답 지연 방지).
  """
  def save_async(%State{} = state) do
    Task.start(fn ->
      try do
        case save(state) do
          :ok -> :ok
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
    dir = campaign_dir(campaign_id)
    summary_path = Path.join(dir, "campaign-summary.json")

    if File.exists?(summary_path) do
      with {:ok, summary} <- read_json(summary_path),
           :ok <- check_schema_version(summary),
           {:ok, characters} <- load_characters(dir),
           {:ok, npcs} <- load_npcs(dir),
           {:ok, exploration_history} <- load_exploration_history(dir),
           {:ok, combat_history} <- load_combat_history(dir),
           {:ok, journal} <- load_journal(dir) do
        context_summary = load_context_summary(dir)

        state =
          State.from_summary(summary)
          |> Map.put(:characters, characters)
          |> Map.put(:npcs, npcs)
          |> Map.put(:exploration_history, exploration_history)
          |> Map.put(:combat_history, combat_history)
          |> Map.put(:journal_entries, journal)
          |> Map.put(:context_summary, context_summary)

        {:ok, state}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  저장된 캠페인 목록을 반환한다 (최근 업데이트 순).
  """
  def list_campaigns do
    campaigns_dir = Path.join(data_dir(), "campaigns")

    if File.exists?(campaigns_dir) do
      case File.ls(campaigns_dir) do
        {:ok, dirs} ->
          dirs
          |> Enum.map(fn dir_name ->
            summary_path = Path.join([campaigns_dir, dir_name, "campaign-summary.json"])

            case read_json(summary_path) do
              {:ok, summary} ->
                %{
                  id: summary["id"],
                  name: summary["name"],
                  updated_at: summary["updated_at"]
                }

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.sort_by(& &1.updated_at, :desc)

        _ ->
          []
      end
    else
      []
    end
  end

  @doc """
  세션 로그를 campaign-log.md에 추가한다.
  """
  def append_session_log(%State{} = state, session_number, summary_text) do
    dir = campaign_dir(state.id)
    log_path = Path.join(dir, "campaign-log.md")

    date_str = Date.utc_today() |> Date.to_iso8601()

    # 파티 현황 섹션
    party_section = format_party_section(state)

    entry = """

    ---

    # 세션 #{session_number} — #{date_str}

    #{summary_text}

    #{party_section}
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

  @doc """
  campaign-log.md 파일에서 세션 요약 목록을 로드한다.
  반환: {:ok, [String.t()]} — 각 항목은 세션 하나의 마크다운 텍스트
  """
  def load_session_log(campaign_id) do
    path = Path.join(campaign_dir(campaign_id), "campaign-log.md")

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

  @doc """
  AI 컨텍스트 요약 로그를 summary_log.jsonl에서 로드한다.
  """
  def load_summary_log(campaign_id) do
    path = Path.join(campaign_dir(campaign_id), "summary_log.jsonl")

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

  @doc """
  컨텍스트 요약 로그를 summary_log.jsonl에 추가한다.
  """
  def append_summary_log(campaign_id, summary_text) do
    dir = campaign_dir(campaign_id)
    File.mkdir_p(dir)
    log_path = Path.join(dir, "summary_log.jsonl")

    entry = Jason.encode!(%{
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "summary" => summary_text
    })

    case File.write(log_path, entry <> "\n", [:append]) do
      :ok -> :ok
      {:error, reason} ->
        Logger.error("요약 로그 저장 실패 [#{campaign_id}]: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  캠페인 데이터를 삭제한다.
  """
  def delete(campaign_id) do
    dir = campaign_dir(campaign_id)

    if File.exists?(dir) do
      File.rm_rf(dir)
      :ok
    else
      :ok
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp check_schema_version(summary) do
    version = summary["schema_version"] || 0

    if version < @schema_version do
      Logger.warning("[Persistence] 구버전 세이브 파일 (v#{version}). 현재 v#{@schema_version}.")
    end

    :ok
  end

  defp data_dir do
    Application.get_env(:trpg_master, :data_dir, "data")
  end

  defp campaign_dir(campaign_id) do
    Path.join([data_dir(), "campaigns", sanitize_filename(campaign_id)])
  end

  # 파일 시스템에 안전하지 않은 문자(/\:*?"<>|)를 _로 치환하고 양쪽 공백을 제거한다.
  defp sanitize_filename(name) do
    name
    |> String.replace(~r/[\/\\:*?"<>|]/, "_")
    |> String.trim()
  end

  defp write_json(path, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> File.write(path, json)
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_json(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    end
  end

  defp save_characters(dir, characters) do
    Enum.each(characters, fn char ->
      name = char["name"] || "unknown"
      path = Path.join([dir, "characters", "#{sanitize_filename(name)}.json"])
      write_json(path, char)
    end)

    :ok
  end

  defp save_npcs(dir, npcs) do
    Enum.each(npcs, fn {name, data} ->
      path = Path.join([dir, "npcs", "#{sanitize_filename(name)}.json"])
      write_json(path, data)
    end)

    :ok
  end

  defp load_characters(dir) do
    chars_dir = Path.join(dir, "characters")

    if File.exists?(chars_dir) do
      case File.ls(chars_dir) do
        {:ok, files} ->
          characters =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(fn file ->
              case read_json(Path.join(chars_dir, file)) do
                {:ok, data} -> data
                _ -> nil
              end
            end)
            |> Enum.reject(&is_nil/1)

          {:ok, characters}

        _ ->
          {:ok, []}
      end
    else
      {:ok, []}
    end
  end

  defp load_npcs(dir) do
    npcs_dir = Path.join(dir, "npcs")

    if File.exists?(npcs_dir) do
      case File.ls(npcs_dir) do
        {:ok, files} ->
          npcs =
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.reduce(%{}, fn file, acc ->
              case read_json(Path.join(npcs_dir, file)) do
                {:ok, data} ->
                  name = data["name"] || Path.rootname(file)
                  Map.put(acc, name, data)

                _ ->
                  acc
              end
            end)

          {:ok, npcs}

        _ ->
          {:ok, %{}}
      end
    else
      {:ok, %{}}
    end
  end

  defp format_party_section(state) do
    chars =
      state.characters
      |> Enum.map(fn c ->
        hp = if c["hp_current"] && c["hp_max"], do: " HP #{c["hp_current"]}/#{c["hp_max"]}", else: ""
        "- #{c["name"]}#{hp}"
      end)
      |> Enum.join("\n")

    quests =
      state.active_quests
      |> Enum.map(fn q -> "- #{q["name"]} [#{q["status"] || "진행중"}]" end)
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

  defp load_exploration_history(dir) do
    path = Path.join(dir, "exploration_history.json")

    if File.exists?(path) do
      read_json(path)
    else
      # 하위호환: 기존 conversation_history.json을 exploration_history로 마이그레이션
      legacy_path = Path.join(dir, "conversation_history.json")

      if File.exists?(legacy_path) do
        Logger.info("[Persistence] 기존 conversation_history.json → exploration_history로 마이그레이션")
        read_json(legacy_path)
      else
        {:ok, []}
      end
    end
  end

  defp load_combat_history(dir) do
    path = Path.join(dir, "combat_history.json")

    if File.exists?(path) do
      read_json(path)
    else
      {:ok, []}
    end
  end

  defp save_context_summary(_dir, nil), do: :ok

  defp save_context_summary(dir, summary) do
    write_json(Path.join(dir, "context_summary.json"), %{"summary" => summary})
  end

  defp load_context_summary(dir) do
    path = Path.join(dir, "context_summary.json")

    case read_json(path) do
      {:ok, %{"summary" => summary}} -> summary
      _ -> nil
    end
  end

  defp load_journal(dir) do
    path = Path.join(dir, "journal.json")

    if File.exists?(path) do
      read_json(path)
    else
      {:ok, []}
    end
  end
end
