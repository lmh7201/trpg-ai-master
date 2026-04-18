defmodule TrpgMaster.AI.Providers.Http do
  @moduledoc false

  require Logger

  @default_connect_timeout 10_000

  def post_json(url, headers, body, opts) do
    :ssl.start()
    :inets.start()

    provider = Keyword.fetch!(opts, :provider)

    request = {String.to_charlist(url), headers, ~c"application/json", Jason.encode!(body)}

    http_opts = [
      timeout: Keyword.fetch!(opts, :timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      ssl: ssl_options()
    ]

    case :httpc.request(:post, request, http_opts, []) do
      {:ok, {{_, status, _}, _headers, resp_body}} when status in 200..299 ->
        decode_success_body(resp_body)

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        body_str = :erlang.list_to_binary(resp_body)
        Logger.error("#{provider} API 오류 #{status}: #{body_str}")

        {:error, {:api_error, status, decode_error_body(body_str)}}

      {:error, {:failed_connect, _}} ->
        {:error, :connection_failed}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("#{provider} HTTP 요청 실패: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  def ssl_options do
    ca_cert_file = System.get_env("SSL_CERT_FILE") || find_cacert_file()

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

  defp decode_success_body(resp_body) do
    case Jason.decode(:erlang.list_to_binary(resp_body)) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, reason} -> {:error, {:json_parse_error, reason}}
    end
  end

  defp decode_error_body(body_str) do
    case Jason.decode(body_str) do
      {:ok, parsed} -> parsed
      _ -> %{"raw" => String.slice(body_str, 0, 300)}
    end
  end

  defp find_cacert_file do
    paths = [
      "/etc/ssl/certs/ca-certificates.crt",
      "/etc/pki/tls/certs/ca-bundle.crt",
      "/opt/homebrew/etc/openssl/cert.pem",
      "/usr/local/etc/openssl/cert.pem",
      "/etc/ssl/cert.pem"
    ]

    Enum.find(paths, List.first(paths), &File.exists?/1)
  end
end
