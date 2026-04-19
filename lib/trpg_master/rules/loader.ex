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

  alias TrpgMaster.Rules.Loader.{Indexer, Local, Manifest, Remote}

  @table :dnd_rules
  @fetch_timeout 60_000

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
    type_counts = Enum.map(Manifest.status_types(), fn type -> {type, list(type) |> length()} end)
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

    Enum.each(Manifest.data_files(), fn spec ->
      Remote.load_data_file(table, spec, token, @fetch_timeout, fn ->
        Local.load_data_file(table, spec)
      end)
    end)

    Enum.each(Manifest.rule_files(), fn filename ->
      Remote.load_rule_file(table, filename, token, @fetch_timeout, fn ->
        Local.load_rule_file(table, filename)
      end)
    end)
  end

  defp load_from_local(table) do
    Enum.each(Manifest.data_files(), &Local.load_data_file(table, &1))

    Enum.each(Manifest.rule_files(), &Local.load_rule_file(table, &1))
  end
end
