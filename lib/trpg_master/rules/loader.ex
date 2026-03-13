defmodule TrpgMaster.Rules.Loader do
  @moduledoc """
  D&D 5e 룰 데이터를 ETS 테이블에 로드하고 조회하는 GenServer.
  앱 시작 시 priv/rules/*.json 파일을 로드한다.

  ETS 테이블: :dnd_rules
  키 형태: {:spell, "파이어볼"}, {:monster, "고블린"} 등
  이름은 downcase + trim으로 정규화된다.
  한국어 이름(name)과 영어 이름(name_en, 있는 경우) 모두 키로 등록한다.
  """

  use GenServer
  require Logger

  @table :dnd_rules

  @file_type_map [
    {"spells.json", :spell},
    {"monsters.json", :monster},
    {"classes.json", :class},
    {"feats.json", :feat},
    {"items.json", :item}
  ]

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc """
  정확한 이름으로 조회 (한국어 또는 영어).
  Returns {:ok, entry} | :not_found
  """
  def lookup(type, name) do
    key = {type, normalize(name)}

    try do
      case :ets.lookup(@table, key) do
        [{^key, entry}] -> {:ok, entry}
        [] -> :not_found
      end
    rescue
      ArgumentError -> :not_found
    end
  end

  @doc """
  부분 문자열 검색. 이름에 query가 포함된 모든 엔트리를 반환한다.
  Returns [entry, ...]
  """
  def search(type, query) do
    normalized_query = normalize(query)

    # ETS match_spec: key = {type, name_str} where name_str contains query
    # We use :ets.select with a match spec filtering by type and substring
    match_spec = [
      {{{type, :"$1"}, :"$2"}, [{:is_binary, :"$1"}],
       [{{:"$1", :"$2"}}]}
    ]

    try do
      :ets.select(@table, match_spec)
    rescue
      ArgumentError -> []
    end
    |> Enum.filter(fn {name_str, _entry} ->
      String.contains?(name_str, normalized_query)
    end)
    |> Enum.map(fn {_name_str, entry} -> entry end)
    |> Enum.uniq()
  end

  @doc """
  특정 타입의 전체 목록을 반환한다.
  Returns [entry, ...]
  """
  def list(type) do
    match_spec = [
      {{{type, :"$1"}, :"$2"}, [], [:"$2"]}
    ]

    try do
      :ets.select(@table, match_spec)
    rescue
      ArgumentError -> []
    end
    |> Enum.uniq()
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    load_all_files(table)
    {:ok, %{table: table}}
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp load_all_files(table) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")

    Enum.each(@file_type_map, fn {filename, type} ->
      path = Path.join(rules_dir, filename)
      load_file(table, path, type)
    end)
  end

  defp load_file(table, path, type) do
    if File.exists?(path) do
      started_at = System.monotonic_time(:millisecond)

      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, entries} when is_list(entries) ->
              count = insert_entries(table, type, entries)
              elapsed = System.monotonic_time(:millisecond) - started_at

              Logger.info(
                "Rules.Loader: #{type} #{count}개 로드 완료 (#{elapsed}ms) — #{path}"
              )

            {:ok, _other} ->
              Logger.warning("Rules.Loader: #{path} — JSON이 배열이 아닙니다. 건너뜁니다.")

            {:error, reason} ->
              Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 빈 상태로 시작합니다.")
    end
  end

  defp insert_entries(table, type, entries) do
    Enum.reduce(entries, 0, fn entry, count ->
      inserted = insert_entry(table, type, entry)
      count + inserted
    end)
  end

  defp insert_entry(table, type, entry) when is_map(entry) do
    ko_name = Map.get(entry, "name")
    en_name = Map.get(entry, "name_en")

    inserted =
      if is_binary(ko_name) && ko_name != "" do
        key = {type, normalize(ko_name)}
        :ets.insert(table, {key, entry})
        1
      else
        0
      end

    if is_binary(en_name) && en_name != "" do
      en_key = {type, normalize(en_name)}
      :ets.insert(table, {en_key, entry})
    end

    inserted
  end

  defp insert_entry(_table, _type, _entry), do: 0

  defp normalize(name) when is_binary(name) do
    name |> String.downcase() |> String.trim()
  end

  defp normalize(name), do: inspect(name)
end
