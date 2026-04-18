defmodule TrpgMaster.AI.Providers.Gemini do
  @moduledoc """
  Google Gemini API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  alias TrpgMaster.AI.Providers.Http
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
      max_tokens = Keyword.get(opts, :max_tokens, 4096)

      gemini_contents = convert_messages(messages)
      gemini_tools = convert_tools(tools)

      body =
        %{
          system_instruction: %{parts: [%{text: system_prompt}]},
          contents: gemini_contents,
          generation_config: %{max_output_tokens: max_tokens}
        }
        |> maybe_add_tools(gemini_tools)

      do_chat_with_retry(api_key, model, body, [], 0)
    end
  end

  # ── 메시지 변환 ──────────────────────────────────────────────────────────────

  # Claude/OpenAI 형식의 메시지를 Gemini contents 형식으로 변환
  defp convert_messages(messages) do
    Enum.flat_map(messages, fn msg ->
      role = msg["role"] || msg[:role]
      content = msg["content"] || msg[:content]

      gemini_role = if role == "assistant", do: "model", else: "user"

      case content do
        text when is_binary(text) ->
          [%{role: gemini_role, parts: [%{text: text}]}]

        # tool_result 블록 목록 (user 역할)
        parts when is_list(parts) ->
          gemini_parts =
            Enum.map(parts, fn part ->
              type = part[:type] || part["type"]

              cond do
                type == "tool_result" ->
                  %{
                    function_response: %{
                      name: part[:tool_use_id] || part["tool_use_id"] || "unknown",
                      response: %{
                        content: part[:content] || part["content"] || ""
                      }
                    }
                  }

                type == "tool_use" ->
                  %{
                    function_call: %{
                      name: part[:name] || part["name"],
                      args: part[:input] || part["input"] || %{}
                    }
                  }

                true ->
                  text_content = part[:text] || part["text"] || ""
                  %{text: text_content}
              end
            end)
            |> Enum.reject(&(&1 == %{text: ""}))

          if gemini_parts == [] do
            []
          else
            [%{role: gemini_role, parts: gemini_parts}]
          end

        _ ->
          []
      end
    end)
  end

  # ── 도구 변환 ────────────────────────────────────────────────────────────────

  defp convert_tools([]), do: []

  defp convert_tools(tools) do
    function_declarations =
      Enum.map(tools, fn tool ->
        name = tool[:name] || tool["name"]
        description = tool[:description] || tool["description"]
        input_schema = tool[:input_schema] || tool["input_schema"] || %{}

        # Gemini는 additionalProperties를 지원하지 않으므로 재귀적으로 제거
        parameters = sanitize_schema(input_schema)

        %{
          name: name,
          description: description,
          parameters: parameters
        }
      end)

    [%{function_declarations: function_declarations}]
  end

  defp sanitize_schema(schema) when is_map(schema) do
    schema
    |> Map.drop(["additionalProperties", :additionalProperties])
    |> Map.new(fn {k, v} -> {k, sanitize_schema(v)} end)
  end

  defp sanitize_schema(schema) when is_list(schema) do
    Enum.map(schema, &sanitize_schema/1)
  end

  defp sanitize_schema(other), do: other

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)

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
    candidate = get_in(response, ["candidates", Access.at(0)]) || %{}
    parts = get_in(candidate, ["content", "parts"]) || []
    finish_reason = candidate["finishReason"]

    function_calls = Enum.filter(parts, &Map.has_key?(&1, "functionCall"))
    text_parts = Enum.filter(parts, &Map.has_key?(&1, "text"))

    if finish_reason == "STOP" && function_calls == [] do
      text =
        text_parts
        |> Enum.map(& &1["text"])
        |> Enum.join("\n")

      {:ok,
       %{
         text: text,
         tool_results: tool_results,
         usage: usage
       }}
    else
      if function_calls != [] do
        {new_tool_results, function_responses} = execute_tools(function_calls)

        # 현재 모델 응답과 함수 결과를 contents에 추가
        # parts 전체를 그대로 포함해야 thought_signature가 유지된다 (Gemini thinking 모델 필수)
        model_turn = %{
          role: "model",
          parts: parts
        }

        user_turn = %{
          role: "user",
          parts: function_responses
        }

        updated_contents = body.contents ++ [model_turn, user_turn]
        updated_body = %{body | contents: updated_contents}

        do_chat_loop(
          api_key,
          model,
          updated_body,
          tool_results ++ new_tool_results,
          iterations_left - 1,
          usage
        )
      else
        # 텍스트만 있는 경우
        text =
          text_parts
          |> Enum.map(& &1["text"])
          |> Enum.join("\n")

        {:ok,
         %{
           text: text,
           tool_results: tool_results,
           usage: usage
         }}
      end
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
