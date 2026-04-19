defmodule TrpgMaster.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude API 프로바이더.
  tool use 루프, 재시도, 프롬프트 캐싱을 포함한다.
  """

  alias TrpgMaster.AI.Providers.Anthropic.Request
  alias TrpgMaster.AI.Providers.Anthropic.Response
  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.Retry
  alias TrpgMaster.AI.Providers.StandardChat
  alias TrpgMaster.AI.Providers.ToolExecution
  alias TrpgMaster.AI.RateLimiter
  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @max_tool_iterations 20
  @timeout 120_000

  @doc """
  Claude API에 메시지를 보내고 응답을 받는다.
  tool use가 발생하면 도구를 실행하고 자동으로 재호출한다.
  """
  def chat(system_prompt, messages, tools \\ [], opts \\ []) do
    api_key = Application.get_env(:trpg_master, :anthropic_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, :no_api_key}
    else
      StandardChat.run(
        provider: "Anthropic",
        body: Request.build(system_prompt, messages, tools, opts),
        context: %{api_key: api_key},
        max_tool_iterations: @max_tool_iterations,
        call_api: &call_api_with_rate_limit/2,
        response_module: Response,
        execute_tools: &execute_tools/1,
        usage_info: &usage_info/2,
        retry_rules: retry_rules()
      )
    end
  end

  defp retry_rules do
    [
      Retry.status_rule(400, 2,
        log: fn attempt, _reason ->
          "Anthropic API 400 오류 — 히스토리 트리밍 후 재시도 (#{attempt}/2)"
        end,
        transform: fn state, _reason ->
          %{state | body: aggressive_trim_history(state.body)}
        end
      ),
      Retry.rate_limit_rule("Anthropic"),
      Retry.server_error_rule("Anthropic", [500, 529])
    ]
  end

  defp aggressive_trim_history(body) do
    messages = body.messages
    take_count = min(max(div(length(messages), 2), 2), length(messages))
    trimmed = Enum.take(messages, -take_count)

    trimmed =
      case trimmed do
        [%{role: "assistant"} | rest] -> rest
        other -> other
      end

    Logger.info("공격적 트리밍: #{length(messages)}개 → #{length(trimmed)}개")
    %{body | messages: trimmed}
  end

  defp call_api_with_rate_limit(%{api_key: api_key}, body) do
    case RateLimiter.check_and_wait() do
      :ok ->
        call_api(api_key, body)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end

  defp usage_info(response, usage) do
    input_tokens = get_in(response, ["usage", "input_tokens"]) || 0
    output_tokens = get_in(response, ["usage", "output_tokens"]) || 0
    cache_read = get_in(response, ["usage", "cache_read_input_tokens"]) || 0
    cache_create = get_in(response, ["usage", "cache_creation_input_tokens"]) || 0

    # ITPM에 카운트되는 토큰: input_tokens + cache_creation (cache_read는 미포함)
    itpm_tokens = input_tokens + cache_create
    RateLimiter.record_usage(itpm_tokens)

    %{
      usage: %{
        input_tokens: usage.input_tokens + input_tokens,
        output_tokens: usage.output_tokens + output_tokens
      },
      log:
        "Claude API 호출 — ITPM: #{itpm_tokens}토큰 (입력:#{input_tokens} + 캐시생성:#{cache_create}), 출력: #{output_tokens}토큰, 캐시읽기: #{cache_read}토큰"
    }
  end

  defp execute_tools(tool_use_blocks) do
    ToolExecution.run(tool_use_blocks,
      provider: "Anthropic",
      extract: fn block ->
        %{
          id: block["id"],
          name: block["name"],
          input: block["input"] || %{}
        }
      end,
      success: fn extracted, result ->
        encoded = Jason.encode!(result)

        %{
          type: "tool_result",
          tool_use_id: extracted.id,
          content: truncate_tool_result(encoded, extracted.name)
        }
      end,
      error: fn extracted, reason ->
        %{
          type: "tool_result",
          tool_use_id: extracted.id,
          is_error: true,
          content: "오류: #{reason}"
        }
      end
    )
  end

  @max_tool_result_chars 3000

  defp truncate_tool_result(encoded, tool_name)
       when byte_size(encoded) > @max_tool_result_chars do
    Logger.info("도구 결과 압축: #{tool_name} — #{byte_size(encoded)}자 → #{@max_tool_result_chars}자")
    String.slice(encoded, 0, @max_tool_result_chars) <> "...(truncated)"
  end

  defp truncate_tool_result(encoded, _tool_name), do: encoded

  # ── HTTP ────────────────────────────────────────────────────────────────────
  defp call_api(api_key, body) do
    headers = [
      {~c"x-api-key", String.to_charlist(api_key)},
      {~c"anthropic-version", ~c"2023-06-01"},
      {~c"anthropic-beta", ~c"prompt-caching-2024-07-31"},
      {~c"content-type", ~c"application/json"}
    ]

    Http.post_json(@api_url, headers, body,
      provider: "Claude",
      timeout: @timeout
    )
  end
end
