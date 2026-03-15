defmodule TrpgMaster.Rules.Loader do
  @moduledoc """
  D&D 5e 룰 데이터를 ETS 테이블에 로드하고 조회하는 GenServer.

  DATA_GITHUB_TOKEN 환경변수가 있으면 GitHub(lmh7201/dnd_reference_ko)에서 직접 fetch.
  없으면 priv/rules/*.json 로컬 파일 사용.

  ETS 테이블: :dnd_rules
  키 형태: {:spell, "파이어볼"}, {:monster, "고블린"} 등
  이름은 downcase + trim으로 정규화. 한국어 + 영어 이중 키 등록.

  ## 파일별 name 필드 구조

  | 파일                | 한국어 키  | 영어 키   | JSON 형태 |
  |---------------------|-----------|----------|----------|
  | spells.json         | nameKo    | name     | list     |
  | monsters.json       | name      | nameEn   | list     |
  | classes.json        | name      | nameEn   | list     |
  | feats.json          | name.ko   | name.en  | list (name은 {ko:,en:} 객체) |
  | items.json          | name      | nameEn   | list     |
  | weapons.json        | nameKo    | name     | dict → weapons 키 |
  | armor.json          | nameKo    | name     | dict → armor 키  |
  | adventuringGear.json| nameKo    | name     | dict → gear 키   |
  """

  use GenServer
  require Logger

  @table :dnd_rules
  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd-reference/src/data"
  @fetch_timeout 60_000

  # {filename, ets_type, name_style, list_key}
  # name_style:
  #   :nameKo_name    — 한국어: nameKo, 영어: name
  #   :name_nameEn    — 한국어: name, 영어: nameEn
  #   :name_object    — name이 {ko: ..., en: ...} 객체
  # list_key:
  #   nil             — JSON 최상위가 배열
  #   "key"           — JSON 최상위가 dict; 해당 키의 배열을 사용
  @file_type_map [
    {"spells.json", :spell, :nameKo_name, nil},
    {"monsters.json", :monster, :name_nameEn, nil},
    {"classes.json", :class, :name_nameEn, nil},
    {"feats.json", :feat, :name_object, nil},
    {"items.json", :item, :name_nameEn, nil},
    {"weapons.json", :item, :nameKo_name, "weapons"},
    {"armor.json", :item, :nameKo_name, "armor"},
    {"adventuringGear.json", :item, :nameKo_name, "gear"}
  ]

  # rules/*.json 파일: 각 파일은 {id, title, intro, sections} 구조의 단일 객체.
  # :rule 타입으로 ETS에 저장. 문서 전체 + 개별 섹션 모두 키 등록.
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
    |> Enum.filter(fn {name_str, _} -> String.contains?(name_str, normalized_query) end)
    |> Enum.map(fn {_, entry} -> entry end)
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
    types = @file_type_map |> Enum.map(fn {_, t, _, _} -> t end) |> Enum.uniq()
    type_counts = Enum.map(types, fn type -> {type, list(type) |> length()} end)
    rule_count = list(:rule) |> length()
    type_counts ++ [{:rule, rule_count}]
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

    totals =
      status()
      |> Enum.map(fn {t, n} -> "#{t}:#{n}" end)
      |> Enum.join(", ")

    Logger.info("Rules.Loader: 로드 완료 — #{totals}")

    {:ok, %{table: table}}
  end

  # ── Load strategies ─────────────────────────────────────────────────────────

  defp load_from_github(table, token) do
    Logger.info("Rules.Loader: DATA_GITHUB_TOKEN 감지됨 → GitHub에서 데이터 fetch 시작")

    Enum.each(@file_type_map, fn {filename, type, name_style, list_key} ->
      url = "#{@github_raw_base}/#{filename}"

      case fetch_json(url, token) do
        {:ok, raw} ->
          entries = extract_list(raw, list_key)
          count = insert_entries(table, type, name_style, entries)
          log_columns(type, entries)
          Logger.info("Rules.Loader: [GitHub] #{filename} → #{type} #{count}개")

        {:error, reason} ->
          Logger.warning(
            "Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체"
          )

          load_local_file(table, filename, type, name_style, list_key)
      end
    end)

    # rules/*.json 로드
    Enum.each(@rules_file_map, fn filename ->
      url = "#{@github_raw_base}/#{filename}"

      case fetch_json(url, token) do
        {:ok, raw} ->
          count = insert_rule_document(table, raw)
          Logger.info("Rules.Loader: [GitHub] #{filename} → rule #{count}개")

        {:error, reason} ->
          Logger.warning(
            "Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체"
          )

          load_local_rule_file(table, filename)
      end
    end)
  end

  defp load_from_local(table) do
    Enum.each(@file_type_map, fn {filename, type, name_style, list_key} ->
      load_local_file(table, filename, type, name_style, list_key)
    end)

    # rules/*.json 로드
    Enum.each(@rules_file_map, fn filename ->
      load_local_rule_file(table, filename)
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
          {:ok, data} -> {:ok, data}
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

  defp load_local_file(table, filename, type, name_style, list_key) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")
    path = Path.join(rules_dir, filename)

    if File.exists?(path) do
      started_at = System.monotonic_time(:millisecond)

      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, raw} ->
              entries = extract_list(raw, list_key)
              count = insert_entries(table, type, name_style, entries)
              elapsed = System.monotonic_time(:millisecond) - started_at
              log_columns(type, entries)
              Logger.info("Rules.Loader: [로컬] #{filename} → #{type} #{count}개 (#{elapsed}ms)")

            {:error, reason} ->
              Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end

  # ── JSON list extraction ────────────────────────────────────────────────────

  # JSON 최상위가 이미 list인 경우
  defp extract_list(data, nil) when is_list(data), do: data
  # JSON 최상위가 dict인 경우 → 지정된 키의 배열 추출
  defp extract_list(data, list_key) when is_map(data) and is_binary(list_key) do
    case Map.get(data, list_key) do
      entries when is_list(entries) -> entries
      _ -> []
    end
  end

  defp extract_list(_, _), do: []

  # ── ETS insert ─────────────────────────────────────────────────────────────

  defp insert_entries(table, type, name_style, entries) do
    Enum.reduce(entries, 0, fn entry, count ->
      count + insert_entry(table, type, name_style, entry)
    end)
  end

  defp insert_entry(table, type, name_style, entry) when is_map(entry) do
    {ko_name, en_name} = extract_names(entry, name_style)

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

  defp insert_entry(_table, _type, _name_style, _entry), do: 0

  # ── Name extraction per style ───────────────────────────────────────────────

  # spells, weapons, armor, adventuringGear: nameKo=한국어, name=영어
  defp extract_names(entry, :nameKo_name) do
    {Map.get(entry, "nameKo"), Map.get(entry, "name")}
  end

  # monsters, classes, items: name=한국어, nameEn=영어
  defp extract_names(entry, :name_nameEn) do
    {Map.get(entry, "name"), Map.get(entry, "nameEn")}
  end

  # feats: name이 {ko: ..., en: ...} 객체
  defp extract_names(entry, :name_object) do
    case Map.get(entry, "name") do
      %{"ko" => ko, "en" => en} -> {ko, en}
      name when is_binary(name) -> {name, nil}
      _ -> {nil, nil}
    end
  end

  # ── Rules document loading ──────────────────────────────────────────────────

  defp load_local_rule_file(table, filename) do
    rules_dir = Application.app_dir(:trpg_master, "priv/rules")
    path = Path.join(rules_dir, filename)

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, raw} ->
              count = insert_rule_document(table, raw)
              Logger.info("Rules.Loader: [로컬] #{filename} → rule #{count}개")

            {:error, reason} ->
              Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")
          end

        {:error, reason} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end

  # rules/*.json은 {id, title, intro, sections} 구조의 단일 문서.
  # 문서 전체를 id로 저장하고, 각 section도 section.id로 저장한다.
  # title의 ko/en 키도 등록하여 한국어/영어 검색을 지원한다.
  defp insert_rule_document(table, %{"id" => doc_id, "sections" => sections} = doc)
       when is_binary(doc_id) and is_list(sections) do
    # 문서 전체를 doc_id로 저장
    :ets.insert(table, {{:rule, normalize(doc_id)}, doc})
    count = 1

    # title의 한국어/영어 키 등록
    title_count = insert_rule_title_keys(table, doc_id, doc)

    # 각 섹션을 section.id로 저장
    section_count =
      Enum.reduce(sections, 0, fn section, acc ->
        acc + insert_rule_section(table, section)
      end)

    count + title_count + section_count
  end

  defp insert_rule_document(_table, _doc), do: 0

  defp insert_rule_title_keys(table, doc_id, doc) do
    title = Map.get(doc, "title", %{})
    ko = Map.get(title, "ko")
    en = Map.get(title, "en")

    ko_count =
      if is_binary(ko) && ko != "" && normalize(ko) != normalize(doc_id) do
        :ets.insert(table, {{:rule, normalize(ko)}, doc})
        1
      else
        0
      end

    en_count =
      if is_binary(en) && en != "" && normalize(en) != normalize(doc_id) do
        :ets.insert(table, {{:rule, normalize(en)}, doc})
        1
      else
        0
      end

    ko_count + en_count
  end

  defp insert_rule_section(table, %{"id" => section_id} = section)
       when is_binary(section_id) do
    :ets.insert(table, {{:rule, normalize(section_id)}, section})

    # 섹션 title의 한국어/영어 키 등록
    title = Map.get(section, "title", %{})
    ko = Map.get(title, "ko")
    en = Map.get(title, "en")

    ko_count =
      if is_binary(ko) && ko != "" && normalize(ko) != normalize(section_id) do
        :ets.insert(table, {{:rule, normalize(ko)}, section})
        1
      else
        0
      end

    en_count =
      if is_binary(en) && en != "" && normalize(en) != normalize(section_id) do
        :ets.insert(table, {{:rule, normalize(en)}, section})
        1
      else
        0
      end

    # 재귀: 하위 content 중 subsection이 있으면 처리
    sub_count =
      case Map.get(section, "content") do
        content when is_list(content) ->
          content
          |> Enum.filter(fn item -> is_map(item) && Map.get(item, "type") == "subsection" end)
          |> Enum.reduce(0, fn sub, acc -> acc + insert_rule_section(table, sub) end)

        _ ->
          0
      end

    1 + ko_count + en_count + sub_count
  end

  defp insert_rule_section(_table, _section), do: 0

  # ── Helpers ─────────────────────────────────────────────────────────────────

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
