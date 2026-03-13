defmodule TrpgMaster.Rules.Loader do
  @moduledoc """
  D&D 5e 룰 데이터를 ETS 테이블에 로드하고 조회하는 GenServer.

  DATA_GITHUB_TOKEN 환경변수가 있으면 GitHub(lmh7201/dnd_reference_ko)에서 직접 fetch.
  없으면 priv/rules/*.json 로컬 파일 사용.

  ETS 테이블: :dnd_rules
  키 형태: {:spell, "파이어볼"}, {:monster, "고블린"} 등
  이름은 downcase + trim으로 정규화. 한국어(name) + 영어(name_en) 이중 키 등록.
  """

  use GenServer
  require Logger

  @table :dnd_rules
  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd_reference/src/data"
  @fetch_timeout 60_000

  @file_type_map [
    {"spells.json", :spell},
    {"monsters.json", :monster},
    {"classes.json", :class},
    {"feats.json", :feat},
    {"items.json", :item}
  ]

  # ── Public API ─────────────────────────────────────────────────────────────

  @doc "정확한 이름으로 조회. Returns {:ok, entry} | :not_found"
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

  @doc "부분 문자열 검색. Returns [entry, ...]"
  def search(type, query) do
    normalized_query = normalize(query)

    match_spec = [
      {{{type, :"$1"}, :"$2"}, [{:is_binary, :"$1"}], [{{:"$1", :"$2"}}]}
    ]

    try do
      :ets.select(@table, match_spec)
    rescue
      ArgumentError -> []
    end
    |> Enum.filter(fn {name_str, _entry} -> String.contains?(name_str, normalized_query) end)
    |> Enum.map(fn {_name_str, entry} -> entry end)
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
  [spell: 300, monster: 450, class: 12, feat: 80, item: 200]
  """
  def status do
    Enum.map(@file_type_map, fn {_filename, type} ->
      {type, list(type) |> length()}
    end)
  end

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

    totals = Enum.map(@file_type_map, fn {_, t} -> "#{t}:#{list(t) |> length()}" end)
    Logger.info("Rules.Loader: 로드 완료 — #{Enum.join(totals, ", ")}")

    {:ok, %{table: table}}
  end

  # ── Load strategies ─────────────────────────────────────────────────────────

  defp load_from_github(table, token) do
    Logger.info("Rules.Loader: DATA_GITHUB_TOKEN 감지됨 → GitHub에서 데이터 fetch 시작")

    Enum.each(@file_type_map, fn {filename, type} ->
      url = "#{@github_raw_base}/#{filename}"

      case fetch_json(url, token) do
        {:ok, entries} ->
          count = insert_entries(table, type, entries)
          log_columns(type, entries)
          Logger.info("Rules.Loader: [GitHub] #{type} #{count}개 로드 완료")

        {:error, reason} ->
          Logger.warning(
            "Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체"
          )

          load_local_file(table, filename, type)
      end
    end)
  end

  defp load_from_local(table) do
    Enum.each(@file_type_map, fn {filename, type} ->
      load_local_file(table, filename, type)
    end)
  end

  # ── GitHub HTTP fetch ───────────────────────────────────────────────────────

  defp fetch_json(url, token) do
    headers = [
      {~c"Authorization", String.to_charlist("token #{token}")},
      {~c"User-Agent", ~c"trpg-ai-master/1.0"}
    ]

    ssl_opts = build_ssl_opts()
    http_opts = [timeout: @fetch_timeout, connect_timeout: 15_000, ssl: ssl_opts]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(:erlang.list_to_binary(body)) do
          {:ok, entries} when is_list(entries) -> {:ok, entries}
          {:ok, _} -> {:error, "응답이 JSON 배열이 아님"}
          {:error, reason} -> {:error, "JSON 파싱 오류: #{inspect(reason)}"}
        end

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, "인증 실패 (401) — DATA_GITHUB_TOKEN을 확인하세요"}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, "파일 없음 (404)"}

      {:ok, {{_, status, _}, _, body}} ->
        body_str = :erlang.list_to_binary(body) |> String.slice(0, 200)
        {:error, "HTTP #{status}: #{body_str}"}

      {:error, reason} ->
        {:error, "HTTP 요청 실패: #{inspect(reason)}"}
    end
  end

  # ── Local file load ─────────────────────────────────────────────────────────

  defp load_local_file(table, filename, type) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")
    path = Path.join(rules_dir, filename)

    if File.exists?(path) do
      started_at = System.monotonic_time(:millisecond)

      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, entries} when is_list(entries) ->
              count = insert_entries(table, type, entries)
              elapsed = System.monotonic_time(:millisecond) - started_at
              log_columns(type, entries)
              Logger.info("Rules.Loader: [로컬] #{type} #{count}개 로드 완료 (#{elapsed}ms)")

            {:ok, _} ->
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

  # ── ETS insert ─────────────────────────────────────────────────────────────

  defp insert_entries(table, type, entries) do
    Enum.reduce(entries, 0, fn entry, count ->
      count + insert_entry(table, type, entry)
    end)
  end

  defp insert_entry(table, type, entry) when is_map(entry) do
    ko_name = Map.get(entry, "name")
    en_name = Map.get(entry, "name_en")

    inserted =
      if is_binary(ko_name) && ko_name != "" do
        :ets.insert(table, {{type, normalize(ko_name)}, entry})
        1
      else
        0
      end

    if is_binary(en_name) && en_name != "" do
      :ets.insert(table, {{type, normalize(en_name)}, entry})
    end

    inserted
  end

  defp insert_entry(_table, _type, _entry), do: 0

  # ── Helpers ─────────────────────────────────────────────────────────────────

  # 각 타입의 첫 엔트리 컬럼을 로그로 출력해 구조 확인
  defp log_columns(_type, []), do: :ok

  defp log_columns(type, [first | _]) when is_map(first) do
    keys = first |> Map.keys() |> Enum.sort() |> Enum.join(", ")
    Logger.info("Rules.Loader: #{type} 컬럼 — [#{keys}]")
  end

  defp normalize(name) when is_binary(name), do: name |> String.downcase() |> String.trim()
  defp normalize(name), do: inspect(name)

  defp build_ssl_opts do
    ca_cert_file = System.get_env("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")

    if File.exists?(ca_cert_file) do
      [
        verify: :verify_peer,
        cacertfile: String.to_charlist(ca_cert_file),
        depth: 10,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      [verify: :verify_none]
    end
  end
end
