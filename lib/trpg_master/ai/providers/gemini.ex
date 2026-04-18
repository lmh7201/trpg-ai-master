defmodule TrpgMaster.AI.Providers.Gemini do
  @moduledoc """
  Google Gemini API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  alias TrpgMaster.AI.Providers.Http
  alias TrpgMaster.AI.Providers.Gemini.Request
  alias TrpgMaster.AI.Providers.Gemini.Response
  alias TrpgMaster.AI.Providers.StandardChat
  alias TrpgMaster.AI.Providers.ToolExecution

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
      StandardChat.run(
        provider: "Gemini",
        body: Request.build(system_prompt, messages, tools, opts),
        context: %{
          api_key: api_key,
          model: Keyword.get(opts, :model, "gemini-2.5-flash")
        },
        max_tool_iterations: @max_tool_iterations,
        call_api: fn %{api_key: current_api_key, model: current_model}, body ->
          call_api(current_api_key, current_model, body)
        end,
        response_module: Response,
        execute_tools: &execute_tools/1,
        usage_info: &usage_info/2,
        retry_rules: [
          TrpgMaster.AI.Providers.Retry.rate_limit_rule("Gemini"),
          TrpgMaster.AI.Providers.Retry.server_error_rule("Gemini", [500, 503])
        ]
      )
    end
  end

  defp usage_info(response, usage) do
    input_tokens = get_in(response, ["usageMetadata", "promptTokenCount"]) || 0
    output_tokens = get_in(response, ["usageMetadata", "candidatesTokenCount"]) || 0
    cached_tokens = get_in(response, ["usageMetadata", "cachedContentTokenCount"]) || 0

    %{
      usage: %{
        input_tokens: usage.input_tokens + input_tokens,
        output_tokens: usage.output_tokens + output_tokens
      },
      log: "Gemini API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰, 캐시: #{cached_tokens}토큰"
    }
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
