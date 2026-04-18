defmodule TrpgMaster.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI Chat Completions API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.OpenAI.Request
  alias TrpgMaster.AI.Providers.Retry
  alias TrpgMaster.AI.Providers.ToolExecution
  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @max_tool_iterations 20
  @timeout 120_000

  @doc """
  OpenAI API에 메시지를 보내고 응답을 받는다.
  tool_calls가 발생하면 도구를 실행하고 자동으로 재호출한다.
  """
  def chat(system_prompt, messages, tools \\ [], opts \\ []) do
    api_key = Application.get_env(:trpg_master, :openai_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, :no_api_key}
    else
      body = Request.build(system_prompt, messages, tools, opts)
      do_chat_with_retry(api_key, body, [], 0)
    end
  end

  # ── 재시도 ───────────────────────────────────────────────────────────────────

  defp do_chat_with_retry(api_key, body, tool_results, retry_count) do
    case do_chat_loop(api_key, body, tool_results, @max_tool_iterations, %{
           input_tokens: 0,
           output_tokens: 0
         }) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_api_error(api_key, body, tool_results, reason, retry_count)
    end
  end

  defp handle_api_error(api_key, body, tool_results, reason, retry_count) do
    case Retry.handle(reason, retry_count, %{body: body, tool_results: tool_results},
           rules: [
             Retry.rate_limit_rule("OpenAI"),
             Retry.server_error_rule("OpenAI", [500, 503])
           ]
         ) do
      {:retry, %{body: updated_body, tool_results: updated_tool_results}, next_retry_count} ->
        do_chat_with_retry(api_key, updated_body, updated_tool_results, next_retry_count)

      {:error, normalized_reason} ->
        {:error, normalized_reason}
    end
  end

  # ── Chat loop ───────────────────────────────────────────────────────────────

  defp do_chat_loop(_api_key, _body, _tool_results, 0, _usage) do
    Logger.warning("OpenAI Tool use 최대 반복 횟수 초과")
    {:error, :max_tool_iterations}
  end

  defp do_chat_loop(api_key, body, tool_results, iterations_left, usage) do
    case call_api(api_key, body) do
      {:ok, response} ->
        input_tokens = get_in(response, ["usage", "prompt_tokens"]) || 0
        output_tokens = get_in(response, ["usage", "completion_tokens"]) || 0

        cached_tokens =
          get_in(response, ["usage", "prompt_tokens_details", "cached_tokens"]) || 0

        new_usage = %{
          input_tokens: usage.input_tokens + input_tokens,
          output_tokens: usage.output_tokens + output_tokens
        }

        Logger.info(
          "OpenAI API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰, 캐시: #{cached_tokens}토큰"
        )

        handle_response(api_key, body, response, tool_results, iterations_left, new_usage)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(api_key, body, response, tool_results, iterations_left, usage) do
    choice = get_in(response, ["choices", Access.at(0)]) || %{}
    message = choice["message"] || %{}
    finish_reason = choice["finish_reason"]
    tool_calls = message["tool_calls"] || []

    if finish_reason == "tool_calls" && length(tool_calls) > 0 do
      {new_tool_results, tool_result_messages} = execute_tools(tool_calls)

      # 현재 assistant 메시지를 히스토리에 추가
      current_messages = body.messages ++ [message | tool_result_messages]
      updated_body = %{body | messages: current_messages}

      do_chat_loop(
        api_key,
        updated_body,
        tool_results ++ new_tool_results,
        iterations_left - 1,
        usage
      )
    else
      text = message["content"] || ""

      {:ok,
       %{
         text: text,
         tool_results: tool_results,
         usage: usage
       }}
    end
  end

  defp execute_tools(tool_calls) do
    ToolExecution.run(tool_calls,
      provider: "OpenAI",
      extract: fn tool_call ->
        %{
          id: tool_call["id"],
          name: get_in(tool_call, ["function", "name"]),
          input: decode_tool_arguments(get_in(tool_call, ["function", "arguments"]))
        }
      end,
      success: fn extracted, result ->
        %{
          role: "tool",
          tool_call_id: extracted.id,
          content: Jason.encode!(result)
        }
      end,
      error: fn extracted, reason ->
        %{
          role: "tool",
          tool_call_id: extracted.id,
          content: "오류: #{reason}"
        }
      end
    )
  end

  defp decode_tool_arguments(arguments) do
    case Jason.decode(arguments || "{}") do
      {:ok, parsed} -> parsed
      _ -> %{}
    end
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp call_api(api_key, body) do
    headers = [
      {~c"authorization", String.to_charlist("Bearer #{api_key}")},
      {~c"content-type", ~c"application/json"}
    ]

    Http.post_json(@api_url, headers, body,
      provider: "OpenAI",
      timeout: @timeout
    )
  end
end
