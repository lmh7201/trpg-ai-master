defmodule TrpgMaster.Rules.Loader do
  @moduledoc """
  D&D 5.5e 룰 데이터를 ETS 테이블에 로드하고 조회하는 GenServer.

  DATA_GITHUB_TOKEN 환경변수가 있으면 GitHub(lmh7201/dnd_reference_ko)에서 직접 fetch.
  없으면 priv/rules/*.json 로컬 파일 사용.

  ETS 테이블: :dnd_rules
  키 형태: {:spell, "파이어볼"}, {:monster, "고블린"} 등
  이름은 downcase + trim으로 정규화. 한국어 + 영어 이중 키 등록.

  ## 파일별 name 필드 구조 (마이그레이션 후 통일 포맷)

  모든 파일이 `name: {ko: "한국어명", en: "English name"}` 형태를 사용한다.

  | 파일                | JSON 형태 | 비고 |
  |---------------------|----------|------|
  | spells.json         | list     | name: {ko, en} |
  | monsters.json       | list     | name: {ko, en} |
  | classes.json        | list     | name: {ko, en} |
  | feats.json          | list     | name: {ko, en} |
  | weapons.json        | list     | 평탄 배열로 변환됨 |
  | armor.json          | list     | 평탄 배열로 변환됨 |
  | adventuringGear.json| dict     | gear 키에 배열 |
  """

  use GenServer
  require Logger

  alias TrpgMaster.Rules.Loader.{Indexer, Source}

  @table :dnd_rules
  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd-reference/src/data"
  @fetch_timeout 60_000

  @file_type_map [
    {"spells.json", :spell, :name_object, nil},
    {"monsters.json", :monster, :name_object, nil},
    {"classes.json", :class, :name_object, nil},
    {"feats.json", :feat, :name_object, nil},
    {"items.json", :item, :name_object, nil},
    {"weapons.json", :item, :name_object, nil},
    {"armor.json", :item, :name_object, nil},
    {"adventuringGear.json", :item, :name_object, "gear"}
  ]

  @rules_file_map [
    "rules/combat.json",
    "rules/conditions.json",
    "rules/actions.json",
    "rules/damage-and-healing.json",
    "rules/d20-tests.json",
    "rules/abilities.json",
    "rules/exploration.json",
    "rules/proficiency.json",
    "rules/social-interaction.json",
    "rules/spellcasting.json"
  ]

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc "정확한 이름으로 조회. Returns {:ok, entry} | :not_found"
  def lookup(type, name) do
    key = {type, Indexer.normalize(name)}

    try do
      case :ets.lookup(@table, key) do
        [{^key, entry}] -> {:ok, entry}
        [] -> :not_found
      end
    rescue
      ArgumentError -> :not_found
    end
  end

  @doc "부분 문자열 검색. Returns [entry, ...]"
  def search(type, query) do
    normalized_query = Indexer.normalize(query)

    match_spec = [
      {{{type, :"$1"}, :"$2"}, [{:is_binary, :"$1"}], [{{:"$1", :"$2"}}]}
    ]

    try do
      :ets.select(@table, match_spec)
    rescue
      ArgumentError -> []
    end
    |> Enum.filter(fn {name_str, _entry} -> String.contains?(name_str, normalized_query) end)
    |> Enum.map(fn {_name, entry} -> entry end)
    |> Enum.uniq()
  end

  @doc "특정 타입의 전체 목록. Returns [entry, ...]"
  def list(type) do
    match_spec = [{{{type, :"$1"}, :"$2"}, [], [:"$2"]}]

    try do
      :ets.select(@table, match_spec)
    rescue
      ArgumentError -> []
    end
    |> Enum.uniq()
  end

  @doc """
  로드 현황 반환. IEx에서 확인용.

      iex> TrpgMaster.Rules.Loader.status()
      [spell: 392, monster: 3, class: 12, feat: 78, item: 120]
  """
  def status do
    types = @file_type_map |> Enum.map(fn {_, type, _, _} -> type end) |> Enum.uniq()
    type_counts = Enum.map(types, fn type -> {type, list(type) |> length()} end)
    rule_count = list(:rule) |> length()
    type_counts ++ [{:rule, rule_count}]
  end

  @doc """
  CR 문자열을 float으로 변환한다.
  "1/4" → 0.25, "1/2" → 0.5, "1" → 1.0, "24" → 24.0
  파싱 불가 시 nil 반환.
  """
  def parse_cr(cr_string) when is_binary(cr_string) do
    cr_string = String.trim(cr_string)

    cond do
      cr_string == "1/8" ->
        0.125

      cr_string == "1/4" ->
        0.25

      cr_string == "1/2" ->
        0.5

      true ->
        case Float.parse(cr_string) do
          {value, _} ->
            value

          :error ->
            case Integer.parse(cr_string) do
              {value, _} -> value * 1.0
              :error -> nil
            end
        end
    end
  end

  def parse_cr(_), do: nil

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ssl.start()
    :inets.start()

    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    token = System.get_env("DATA_GITHUB_TOKEN")

    if is_binary(token) && token != "" do
      load_from_github(table, token)
    else
      Logger.info("Rules.Loader: DATA_GITHUB_TOKEN 없음 → 로컬 priv/rules/ 파일 사용")
      load_from_local(table)
    end

    totals =
      status()
      |> Enum.map(fn {type, count} -> "#{type}:#{count}" end)
      |> Enum.join(", ")

    Logger.info("Rules.Loader: 로드 완료 — #{totals}")

    {:ok, %{table: table}}
  end

  # ── Load strategies ─────────────────────────────────────────────────────────

  defp load_from_github(table, token) do
    Logger.info("Rules.Loader: DATA_GITHUB_TOKEN 감지됨 → GitHub에서 데이터 fetch 시작")

    Enum.each(@file_type_map, fn {filename, type, name_style, list_key} ->
      url = "#{@github_raw_base}/#{filename}"

      case Source.fetch_json(url, token, @fetch_timeout) do
        {:ok, raw} ->
          entries = Indexer.extract_list(raw, list_key)
          count = Indexer.insert_entries(table, type, name_style, entries)
          Indexer.log_columns(type, entries)
          Logger.info("Rules.Loader: [GitHub] #{filename} → #{type} #{count}개")

        {:error, reason} ->
          Logger.warning("Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체")

          load_local_file(table, filename, type, name_style, list_key)
      end
    end)

    Enum.each(@rules_file_map, fn filename ->
      url = "#{@github_raw_base}/#{filename}"

      case Source.fetch_json(url, token, @fetch_timeout) do
        {:ok, raw} ->
          count = Indexer.insert_rule_document(table, raw)
          Logger.info("Rules.Loader: [GitHub] #{filename} → rule #{count}개")

        {:error, reason} ->
          Logger.warning("Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체")

          load_local_rule_file(table, filename)
      end
    end)
  end

  defp load_from_local(table) do
    Enum.each(@file_type_map, fn {filename, type, name_style, list_key} ->
      load_local_file(table, filename, type, name_style, list_key)
    end)

    Enum.each(@rules_file_map, fn filename ->
      load_local_rule_file(table, filename)
    end)
  end

  # ── Local file load ─────────────────────────────────────────────────────────

  defp load_local_file(table, filename, type, name_style, list_key) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")
    path = Path.join(rules_dir, filename)

    if File.exists?(path) do
      started_at = System.monotonic_time(:millisecond)

      case Source.read_json_file(path) do
        {:ok, raw} ->
          entries = Indexer.extract_list(raw, list_key)
          count = Indexer.insert_entries(table, type, name_style, entries)
          elapsed = System.monotonic_time(:millisecond) - started_at
          Indexer.log_columns(type, entries)
          Logger.info("Rules.Loader: [로컬] #{filename} → #{type} #{count}개 (#{elapsed}ms)")

        {:error, {:decode, reason}} ->
          Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")

        {:error, {:read, reason}} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end

  defp load_local_rule_file(table, filename) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")
    path = Path.join(rules_dir, filename)

    if File.exists?(path) do
      case Source.read_json_file(path) do
        {:ok, raw} ->
          count = Indexer.insert_rule_document(table, raw)
          Logger.info("Rules.Loader: [로컬] #{filename} → rule #{count}개")

        {:error, {:decode, reason}} ->
          Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")

        {:error, {:read, reason}} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end
end
