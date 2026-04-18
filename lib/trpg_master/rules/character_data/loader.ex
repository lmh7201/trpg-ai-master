defmodule TrpgMaster.Rules.CharacterData.Loader do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData.Store
  require Logger

  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd-reference/src/data"
  @fetch_timeout 60_000

  @data_mappings [
    {:classes, "classes.json"},
    {:races, "races.json"},
    {:backgrounds, "backgrounds.json"},
    {:feats, "feats.json"},
    {:spells, "spells.json"},
    {:class_features, "classFeatures.json"},
    {:subclasses, "subclasses.json"},
    {:subclass_features, "subclassFeatures.json"},
    {:weapons, "weapons.json"},
    {:armor, "armor.json"},
    {:adventuring_gear, "adventuringGear.json"},
    {:tools, "tools.json"},
    {:monsters, "monsters.json"}
  ]

  def load do
    :ssl.start()
    :inets.start()
    Store.init_table()

    token = System.get_env("DATA_GITHUB_TOKEN")

    if is_binary(token) && token != "" do
      load_from_github(token)
    else
      Logger.info("CharacterData: DATA_GITHUB_TOKEN 없음 → 로컬 priv/data/ 파일 사용")
      load_from_local()
    end
  end

  defp load_from_github(token) do
    Logger.info("CharacterData: DATA_GITHUB_TOKEN 감지됨 → GitHub에서 데이터 fetch 시작")

    for {key, file} <- @data_mappings do
      url = "#{@github_raw_base}/#{file}"

      case fetch_json(url, token) do
        {:ok, data} ->
          Store.replace(key, data)
          Logger.info("CharacterData: [GitHub] #{file} → #{Store.data_count(data)}건")

        {:error, reason} ->
          Logger.warning("CharacterData: [GitHub] #{file} fetch 실패 (#{reason}) → 로컬 파일로 대체")
          load_local_file(key, file)
      end
    end
  end

  defp load_from_local do
    Logger.info("CharacterData: priv/data/srd/ 에서 로드 시작")

    for {key, file} <- @data_mappings do
      load_local_file(key, Path.join("srd", file), :replace)
    end

    unless srd_only?() do
      Logger.info("CharacterData: srd_only=false → priv/data/phb/ 데이터 병합")

      for {key, file} <- @data_mappings do
        load_local_file(key, Path.join("phb", file), :merge)
      end
    end

    case Application.get_env(:trpg_master, :extra_data_dir) do
      nil -> :ok
      dir -> load_from_extra_dir(dir)
    end
  end

  defp load_from_extra_dir(dir) do
    if File.dir?(dir) do
      Logger.info("CharacterData: 외부 경로 #{dir} 에서 추가 데이터 병합")

      for {key, file} <- @data_mappings do
        path = Path.join(dir, file)

        if File.exists?(path) do
          case File.read(path) do
            {:ok, content} ->
              case Jason.decode(content) do
                {:ok, new_data} ->
                  Store.merge(key, new_data)
                  Logger.info("CharacterData: [외부] #{file} → #{Store.data_count(new_data)}건 병합")

                {:error, reason} ->
                  Logger.warning("CharacterData: JSON 파싱 실패 — #{path}: #{inspect(reason)}")
              end

            {:error, reason} ->
              Logger.warning("CharacterData: 파일 읽기 실패 — #{path}: #{inspect(reason)}")
          end
        end
      end
    else
      Logger.warning("CharacterData: DND_EXTRA_DATA_DIR 경로가 존재하지 않습니다 — #{dir}")
    end
  end

  defp load_local_file(key, file) do
    load_local_file(key, Path.join("srd", file), :replace)

    unless srd_only?() do
      load_local_file(key, Path.join("phb", file), :merge)
    end
  end

  defp load_local_file(key, relative_path, mode) do
    path = Application.app_dir(:trpg_master, Path.join("priv/data", relative_path))

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, new_data} ->
            case mode do
              :replace -> Store.replace(key, new_data)
              :merge -> Store.merge(key, new_data)
            end

            Logger.info(
              "CharacterData: [로컬/#{mode}] #{relative_path} → #{Store.data_count(new_data)}건"
            )

          {:error, reason} ->
            Logger.warning("CharacterData: JSON 파싱 실패 — #{relative_path}: #{inspect(reason)}")
        end

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        Logger.warning("CharacterData: 파일 읽기 실패 — #{relative_path}: #{inspect(reason)}")
    end
  end

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

  defp srd_only?, do: Application.get_env(:trpg_master, :srd_only, true)
end
