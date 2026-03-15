defmodule TrpgMaster.AI.Client do
  @moduledoc """
  Claude API 호출 + tool use 루프.
  Erlang :httpc를 사용하여 외부 HTTP 의존성 없이 구현.
  에러 발생 시 자동 재시도 (토큰 한도, rate limit, 서버 에러).
  """

  alias TrpgMaster.AI.RateLimiter
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @max_tool_iterations 5
  @timeout 120_000

  @doc """
  Claude API에 메시지를 보내고 응답을 받는다.
  tool use가 발생하면 도구를 실행하고 자동으로 재호출한다.

  옵션:
    - model: 사용할 Claude 모델 (기본값: 설정된 모델)
    - max_tokens: 최대 출력 토큰 (기본값: 4096)

  반환값:
    {:ok, %{text: String.t(), tool_results: [map()], usage: map()}}
    {:error, term()}
  """
  def chat(system_prompt, messages, tools \\ [], opts \\ []) do
    api_key = Application.get_env(:trpg_master, :anthropic_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, :no_api_key}
    else
      selected_model = Keyword.get(opts, :model, model())
      max_tokens = Keyword.get(opts, :max_tokens, 4096)

      # 시스템 프롬프트를 캐시 가능한 배열 형태로 변환
      system_blocks = [
        %{type: "text", text: system_prompt, cache_control: %{type: "ephemeral"}}
      ]

      # 도구 정의의 마지막 항목에 cache_control 추가
      cached_tools = add_cache_control_to_tools(tools)

      body = %{
        model: selected_model,
        max_tokens: max_tokens,
        system: system_blocks,
        messages: messages,
        tools: cached_tools
      }

      do_chat_with_retry(api_key, body, 0)
    end
  end

  # ── 재시도 래퍼 ─────────────────────────────────────────────────────────────

  defp do_chat_with_retry(api_key, body, retry_count) do
    case do_chat_loop(api_key, body, [], @max_tool_iterations, %{
           input_tokens: 0,
           output_tokens: 0
         }) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_api_error(api_key, body, reason, retry_count)
    end
  end

  defp handle_api_error(api_key, body, {:api_error, 400, _error_body}, retry_count)
       when retry_count < 2 do
    # 토큰 한도 초과 — 히스토리를 공격적으로 트리밍 후 재시도
    Logger.warning("API 400 오류 — 히스토리 트리밍 후 재시도 (#{retry_count + 1}/2)")
    trimmed_body = aggressive_trim_history(body)
    do_chat_with_retry(api_key, trimmed_body, retry_count + 1)
  end

  defp handle_api_error(api_key, body, {:api_error, 429, _error_body}, retry_count)
       when retry_count < 3 do
    # Rate limit — 지수 백오프 후 재시도
    wait_ms = 2000 * (retry_count + 1)
    Logger.warning("Rate limit — #{wait_ms}ms 대기 후 재시도 (#{retry_count + 1}/3)")
    Process.sleep(wait_ms)
    do_chat_with_retry(api_key, body, retry_count + 1)
  end

  defp handle_api_error(api_key, body, {:api_error, status, _error_body}, retry_count)
       when status in [500, 529] and retry_count < 2 do
    # 서버 에러 — 잠시 대기 후 재시도
    Logger.warning("서버 에러 #{status} — 3초 대기 후 재시도 (#{retry_count + 1}/2)")
    Process.sleep(3000)
    do_chat_with_retry(api_key, body, retry_count + 1)
  end

  defp handle_api_error(_api_key, _body, {:api_error, 401, _}, _retry_count) do
    {:error, :invalid_api_key}
  end

  defp handle_api_error(_api_key, _body, reason, _retry_count) do
    {:error, reason}
  end

  # 도구 정의의 마지막 항목에 cache_control을 추가하여 캐싱 활성화
  defp add_cache_control_to_tools([]), do: []

  defp add_cache_control_to_tools(tools) when is_list(tools) do
    {last, rest} = List.pop_at(tools, -1)
    rest ++ [Map.put(last, :cache_control, %{type: "ephemeral"})]
  end

  # 히스토리를 절반으로 줄이는 공격적 트리밍
  defp aggressive_trim_history(body) do
    messages = body.messages
    half = max(div(length(messages), 2), 2)
    # 최신 메시지의 절반만 유지, user 메시지로 시작해야 함
    trimmed = Enum.take(messages, -half)

    trimmed =
      case trimmed do
        [%{role: "assistant"} | rest] -> rest
        other -> other
      end

    Logger.info("공격적 트리밍: #{length(messages)}개 → #{length(trimmed)}개")
    %{body | messages: trimmed}
  end

  # ── Chat loop ───────────────────────────────────────────────────────────────

  defp do_chat_loop(_api_key, _body, _tool_results, 0, _usage) do
    Logger.warning("Tool use 최대 반복 횟수 초과")
    {:error, :max_tool_iterations}
  end

  defp do_chat_loop(api_key, body, tool_results, iterations_left, usage) do
    # Rate limiter: API 호출 전 토큰 사용량 확인 및 대기
    case RateLimiter.check_and_wait() do
      :ok ->
        case call_api(api_key, body) do
          {:ok, response} ->
            input_tokens = get_in(response, ["usage", "input_tokens"]) || 0
            output_tokens = get_in(response, ["usage", "output_tokens"]) || 0

            # Rate limiter에 실제 사용량 기록
            RateLimiter.record_usage(input_tokens)

            new_usage = %{
              input_tokens: usage.input_tokens + input_tokens,
              output_tokens: usage.output_tokens + output_tokens
            }

            cache_read = get_in(response, ["usage", "cache_read_input_tokens"]) || 0
            cache_create = get_in(response, ["usage", "cache_creation_input_tokens"]) || 0

            Logger.info(
              "Claude API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰, 캐시읽기: #{cache_read}토큰, 캐시생성: #{cache_create}토큰"
            )

            handle_response(api_key, body, response, tool_results, iterations_left, new_usage)

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp handle_response(api_key, body, response, tool_results, iterations_left, usage) do
    content = Map.get(response, "content", [])
    stop_reason = Map.get(response, "stop_reason")

    text_parts =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])

    tool_use_blocks =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))

    if stop_reason == "tool_use" && length(tool_use_blocks) > 0 do
      {new_tool_results, tool_result_blocks} = execute_tools(tool_use_blocks)

      updated_messages =
        body.messages ++
          [
            %{role: "assistant", content: content},
            %{role: "user", content: tool_result_blocks}
          ]

      updated_body = %{body | messages: updated_messages}

      do_chat_loop(
        api_key,
        updated_body,
        tool_results ++ new_tool_results,
        iterations_left - 1,
        usage
      )
    else
      final_text = Enum.join(text_parts, "\n")

      {:ok,
       %{
         text: final_text,
         tool_results: tool_results,
         usage: usage
       }}
    end
  end

  defp execute_tools(tool_use_blocks) do
    results =
      Enum.map(tool_use_blocks, fn block ->
        tool_name = block["name"]
        tool_input = block["input"]
        tool_use_id = block["id"]

        Logger.info("도구 실행: #{tool_name} — #{inspect(tool_input)}")

        case TrpgMaster.AI.Tools.execute(tool_name, tool_input) do
          {:ok, result} ->
            {%{tool: tool_name, input: tool_input, result: result},
             %{
               type: "tool_result",
               tool_use_id: tool_use_id,
               content: Jason.encode!(result)
             }}

          {:error, reason} ->
            {%{tool: tool_name, input: tool_input, error: reason},
             %{
               type: "tool_result",
               tool_use_id: tool_use_id,
               is_error: true,
               content: "오류: #{reason}"
             }}
        end
      end)

    {Enum.map(results, &elem(&1, 0)), Enum.map(results, &elem(&1, 1))}
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp call_api(api_key, body) do
    :ssl.start()
    :inets.start()

    json_body = Jason.encode!(body)

    headers = [
      {~c"x-api-key", String.to_charlist(api_key)},
      {~c"anthropic-version", ~c"2023-06-01"},
      {~c"anthropic-beta", ~c"prompt-caching-2024-07-31"},
      {~c"content-type", ~c"application/json"}
    ]

    ssl_opts = ssl_options()

    http_opts = [
      timeout: @timeout,
      connect_timeout: 10_000,
      ssl: ssl_opts
    ]

    request = {String.to_charlist(@api_url), headers, ~c"application/json", json_body}

    case :httpc.request(:post, request, http_opts, []) do
      {:ok, {{_, status, _}, _headers, resp_body}} when status in 200..299 ->
        case Jason.decode(:erlang.list_to_binary(resp_body)) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        body_str = :erlang.list_to_binary(resp_body)
        Logger.error("Claude API 오류 #{status}: #{body_str}")

        error_body =
          case Jason.decode(body_str) do
            {:ok, parsed} -> parsed
            _ -> %{"raw" => String.slice(body_str, 0, 300)}
          end

        {:error, {:api_error, status, error_body}}

      {:error, {:failed_connect, _}} ->
        {:error, :connection_failed}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("HTTP 요청 실패: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp ssl_options do
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

  defp model do
    Application.get_env(:trpg_master, :ai_model, "claude-sonnet-4-20250514")
  end

  @doc """
  API 에러 atom/tuple을 사용자 친화적인 한국어 메시지로 변환한다.
  """
  def format_error(:no_api_key), do: "ANTHROPIC_API_KEY가 설정되지 않았습니다."
  def format_error(:invalid_api_key), do: "API 키가 올바르지 않습니다. 설정을 확인해주세요."
  def format_error(:timeout), do: "AI 응답이 너무 오래 걸리고 있습니다. 다시 시도해주세요."
  def format_error(:connection_failed), do: "네트워크 연결에 실패했습니다. 인터넷 연결을 확인해주세요."
  def format_error(:max_tool_iterations), do: "도구 실행이 너무 많아 중단되었습니다. 다시 시도해주세요."
  def format_error(:rate_limited), do: "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, 400, body}) do
    msg = get_in(body, ["error", "message"]) || ""

    if String.contains?(msg, "token") do
      "대화가 너무 길어져서 이전 대화를 정리했습니다. 계속 진행해주세요."
    else
      "요청 오류가 발생했습니다. 다시 시도해주세요."
    end
  end

  def format_error({:api_error, 429, _}), do: "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, status, _}) when status in [500, 529],
    do: "일시적인 오류가 발생했습니다. 잠시 후 다시 시도해주세요."

  def format_error({:api_error, status, _}), do: "API 오류 (#{status}). 다시 시도해주세요."

  def format_error(reason) when is_binary(reason), do: reason
  def format_error(reason), do: "오류가 발생했습니다: #{inspect(reason)}"
end
