defmodule TrpgMaster.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI Chat Completions API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.OpenAI.Request
  alias TrpgMaster.AI.Providers.OpenAI.Response
  alias TrpgMaster.AI.Providers.StandardChat
  alias TrpgMaster.AI.Providers.ToolExecution

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
      StandardChat.run(
        provider: "OpenAI",
        body: Request.build(system_prompt, messages, tools, opts),
        context: %{api_key: api_key},
        max_tool_iterations: @max_tool_iterations,
        call_api: fn %{api_key: current_api_key}, body -> call_api(current_api_key, body) end,
        response_module: Response,
        execute_tools: &execute_tools/1,
        usage_info: &usage_info/2,
        retry_rules: [
          TrpgMaster.AI.Providers.Retry.rate_limit_rule("OpenAI"),
          TrpgMaster.AI.Providers.Retry.server_error_rule("OpenAI", [500, 503])
        ]
      )
    end
  end

  defp usage_info(response, usage) do
    input_tokens = get_in(response, ["usage", "prompt_tokens"]) || 0
    output_tokens = get_in(response, ["usage", "completion_tokens"]) || 0
    cached_tokens = get_in(response, ["usage", "prompt_tokens_details", "cached_tokens"]) || 0

    %{
      usage: %{
        input_tokens: usage.input_tokens + input_tokens,
        output_tokens: usage.output_tokens + output_tokens
      },
      log: "OpenAI API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰, 캐시: #{cached_tokens}토큰"
    }
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
