defmodule TrpgMaster.Rules.Loader.Source do
  @moduledoc false

  def fetch_json(url, token, timeout) do
    headers = [
      {~c"Authorization", String.to_charlist("token #{token}")},
      {~c"User-Agent", ~c"trpg-ai-master/1.0"}
    ]

    ssl_opts = build_ssl_opts()
    http_opts = [timeout: timeout, connect_timeout: 15_000, ssl: ssl_opts]

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

  def read_json_file(path) do
    with {:ok, content} <- File.read(path),
         {:ok, data} <- Jason.decode(content) do
      {:ok, data}
    else
      {:error, reason} when is_struct(reason) ->
        {:error, {:decode, reason}}

      {:error, reason} ->
        if File.exists?(path) do
          {:error, {:decode, reason}}
        else
          {:error, {:read, reason}}
        end
    end
  rescue
    error in Jason.DecodeError ->
      {:error, {:decode, error}}
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
end
