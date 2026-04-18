defmodule TrpgMaster.AI.Providers.Anthropic do
  @moduledoc """
  Anthropic Claude API 프로바이더.
  tool use 루프, 재시도, 프롬프트 캐싱을 포함한다.
  """

  alias TrpgMaster.AI.Providers.Anthropic.Request
  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.Retry
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
      body = Request.build(system_prompt, messages, tools, opts)
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

  defp handle_api_error(api_key, body, reason, retry_count) do
    case Retry.handle(reason, retry_count, body,
           rules: [
             Retry.status_rule(400, 2,
               log: fn attempt, _reason ->
                 "Anthropic API 400 오류 — 히스토리 트리밍 후 재시도 (#{attempt}/2)"
               end,
               transform: fn retry_body, _reason -> aggressive_trim_history(retry_body) end
             ),
             Retry.rate_limit_rule("Anthropic"),
             Retry.server_error_rule("Anthropic", [500, 529])
           ]
         ) do
      {:retry, updated_body, next_retry_count} ->
        do_chat_with_retry(api_key, updated_body, next_retry_count)

      {:error, normalized_reason} ->
        {:error, normalized_reason}
    end
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

  # ── Chat loop ───────────────────────────────────────────────────────────────

  defp do_chat_loop(_api_key, _body, _tool_results, 0, _usage) do
    Logger.warning("Tool use 최대 반복 횟수 초과")
    {:error, :max_tool_iterations}
  end

  defp do_chat_loop(api_key, body, tool_results, iterations_left, usage) do
    case RateLimiter.check_and_wait() do
      :ok ->
        case call_api(api_key, body) do
          {:ok, response} ->
            input_tokens = get_in(response, ["usage", "input_tokens"]) || 0
            output_tokens = get_in(response, ["usage", "output_tokens"]) || 0
            cache_read = get_in(response, ["usage", "cache_read_input_tokens"]) || 0
            cache_create = get_in(response, ["usage", "cache_creation_input_tokens"]) || 0

            # ITPM에 카운트되는 토큰: input_tokens + cache_creation (cache_read는 미포함)
            itpm_tokens = input_tokens + cache_create
            RateLimiter.record_usage(itpm_tokens)

            new_usage = %{
              input_tokens: usage.input_tokens + input_tokens,
              output_tokens: usage.output_tokens + output_tokens
            }

            Logger.info(
              "Claude API 호출 — ITPM: #{itpm_tokens}토큰 (입력:#{input_tokens} + 캐시생성:#{cache_create}), 출력: #{output_tokens}토큰, 캐시읽기: #{cache_read}토큰"
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

      # 도구 호출 전에 텍스트가 있었다면, 해당 텍스트가 유저에게 전달되지 않았음을 안내
      has_preceding_text = Enum.any?(text_parts, &(String.trim(&1) != ""))

      user_content =
        if has_preceding_text do
          tool_result_blocks ++
            [
              %{
                type: "text",
                text:
                  "[시스템] 위 assistant 메시지의 text 부분은 플레이어에게 전달되지 않았습니다. " <>
                    "최종 응답에 도구 호출 전에 작성했던 서술 내용을 자연스럽게 포함하여 완전한 장면을 작성하세요."
              }
            ]
        else
          tool_result_blocks
        end

      updated_messages =
        body.messages ++
          [
            %{role: "assistant", content: content},
            %{role: "user", content: user_content}
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
