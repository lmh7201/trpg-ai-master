defmodule TrpgMaster.AI.Providers.Gemini do
  @moduledoc """
  Google Gemini API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.Gemini.Request
  alias TrpgMaster.AI.Providers.Gemini.Response
  alias TrpgMaster.AI.Providers.Retry
  alias TrpgMaster.AI.Providers.ToolExecution
  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"
  @max_tool_iterations 20
  @timeout 120_000

  @doc """
  Gemini API에 메시지를 보내고 응답을 받는다.
  functionCall이 발생하면 도구를 실행하고 자동으로 재호출한다.
  """
  def chat(system_prompt, messages, tools \\ [], opts \\ []) do
    api_key = Application.get_env(:trpg_master, :google_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, :no_api_key}
    else
      model = Keyword.get(opts, :model, "gemini-2.5-flash")
      body = Request.build(system_prompt, messages, tools, opts)
      do_chat_with_retry(api_key, model, body, [], 0)
    end
  end

  # ── 재시도 ───────────────────────────────────────────────────────────────────

  defp do_chat_with_retry(api_key, model, body, tool_results, retry_count) do
    case do_chat_loop(api_key, model, body, tool_results, @max_tool_iterations, %{
           input_tokens: 0,
           output_tokens: 0
         }) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        handle_api_error(api_key, model, body, tool_results, reason, retry_count)
    end
  end

  defp handle_api_error(api_key, model, body, tool_results, reason, retry_count) do
    case Retry.handle(reason, retry_count, %{body: body, tool_results: tool_results},
           rules: [
             Retry.rate_limit_rule("Gemini"),
             Retry.server_error_rule("Gemini", [500, 503])
           ]
         ) do
      {:retry, %{body: updated_body, tool_results: updated_tool_results}, next_retry_count} ->
        do_chat_with_retry(api_key, model, updated_body, updated_tool_results, next_retry_count)

      {:error, normalized_reason} ->
        {:error, normalized_reason}
    end
  end

  # ── Chat loop ───────────────────────────────────────────────────────────────

  defp do_chat_loop(_api_key, _model, _body, _tool_results, 0, _usage) do
    Logger.warning("Gemini Tool use 최대 반복 횟수 초과")
    {:error, :max_tool_iterations}
  end

  defp do_chat_loop(api_key, model, body, tool_results, iterations_left, usage) do
    case call_api(api_key, model, body) do
      {:ok, response} ->
        input_tokens =
          get_in(response, ["usageMetadata", "promptTokenCount"]) || 0

        output_tokens =
          get_in(response, ["usageMetadata", "candidatesTokenCount"]) || 0

        cached_tokens =
          get_in(response, ["usageMetadata", "cachedContentTokenCount"]) || 0

        new_usage = %{
          input_tokens: usage.input_tokens + input_tokens,
          output_tokens: usage.output_tokens + output_tokens
        }

        Logger.info(
          "Gemini API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰, 캐시: #{cached_tokens}토큰"
        )

        handle_response(api_key, model, body, response, tool_results, iterations_left, new_usage)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(api_key, model, body, response, tool_results, iterations_left, usage) do
    if Response.tool_loop?(response) do
      function_calls = Response.tool_calls(response)
      {new_tool_results, function_responses} = execute_tools(function_calls)
      updated_body = Response.append_tool_results(body, response, function_responses)

      do_chat_loop(
        api_key,
        model,
        updated_body,
        tool_results ++ new_tool_results,
        iterations_left - 1,
        usage
      )
    else
      {:ok,
       %{
         text: Response.completion_text(response),
         tool_results: tool_results,
         usage: usage
       }}
    end
  end

  defp execute_tools(function_calls) do
    ToolExecution.run(function_calls,
      provider: "Gemini",
      extract: fn function_call ->
        fc_data = function_call["functionCall"] || function_call

        %{
          name: fc_data["name"],
          input: fc_data["args"] || %{}
        }
      end,
      success: fn extracted, result ->
        %{
          function_response: %{
            name: extracted.name,
            response: %{content: Jason.encode!(result)}
          }
        }
      end,
      error: fn extracted, reason ->
        %{
          function_response: %{
            name: extracted.name,
            response: %{error: "오류: #{reason}"}
          }
        }
      end
    )
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp call_api(api_key, model, body) do
    url = "#{@base_url}/#{model}:generateContent?key=#{api_key}"

    headers = [
      {~c"content-type", ~c"application/json"}
    ]

    Http.post_json(url, headers, body,
      provider: "Gemini",
      timeout: @timeout
    )
  end
end
