defmodule TrpgMaster.AI.Providers.Gemini do
  @moduledoc """
  Google Gemini API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  require Logger

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"
  @max_tool_iterations 5
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

        # Gemini는 additionalProperties를 지원하지 않으므로 제거
        parameters = Map.drop(input_schema, ["additionalProperties", :additionalProperties])

        %{
          name: name,
          description: description,
          parameters: parameters
        }
      end)

    [%{function_declarations: function_declarations}]
  end

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

  defp handle_api_error(api_key, model, body, tool_results, {:api_error, 429, _}, retry_count)
       when retry_count < 3 do
    wait_ms = 2000 * (retry_count + 1)
    Logger.warning("Gemini Rate limit — #{wait_ms}ms 대기 후 재시도 (#{retry_count + 1}/3)")
    Process.sleep(wait_ms)
    do_chat_with_retry(api_key, model, body, tool_results, retry_count + 1)
  end

  defp handle_api_error(api_key, model, body, tool_results, {:api_error, status, _}, retry_count)
       when status in [500, 503] and retry_count < 2 do
    Logger.warning("Gemini 서버 에러 #{status} — 3초 대기 후 재시도 (#{retry_count + 1}/2)")
    Process.sleep(3000)
    do_chat_with_retry(api_key, model, body, tool_results, retry_count + 1)
  end

  defp handle_api_error(_api_key, _model, _body, _tool_results, {:api_error, 401, _}, _) do
    {:error, :invalid_api_key}
  end

  defp handle_api_error(_api_key, _model, _body, _tool_results, reason, _) do
    {:error, reason}
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

        new_usage = %{
          input_tokens: usage.input_tokens + input_tokens,
          output_tokens: usage.output_tokens + output_tokens
        }

        Logger.info(
          "Gemini API 호출 — 입력: #{input_tokens}토큰, 출력: #{output_tokens}토큰"
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
        model_turn = %{
          role: "model",
          parts: Enum.map(function_calls, fn fc ->
            %{function_call: fc["functionCall"]}
          end)
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
    results =
      Enum.map(function_calls, fn fc ->
        fc_data = fc["functionCall"] || fc
        tool_name = fc_data["name"]
        tool_input = fc_data["args"] || %{}

        Logger.info("Gemini 도구 실행: #{tool_name} — #{inspect(tool_input)}")

        case TrpgMaster.AI.Tools.execute(tool_name, tool_input) do
          {:ok, result} ->
            {%{tool: tool_name, input: tool_input, result: result},
             %{
               function_response: %{
                 name: tool_name,
                 response: %{content: Jason.encode!(result)}
               }
             }}

          {:error, reason} ->
            {%{tool: tool_name, input: tool_input, error: reason},
             %{
               function_response: %{
                 name: tool_name,
                 response: %{error: "오류: #{reason}"}
               }
             }}
        end
      end)

    {Enum.map(results, &elem(&1, 0)), Enum.map(results, &elem(&1, 1))}
  end

  # ── HTTP ────────────────────────────────────────────────────────────────────

  defp call_api(api_key, model, body) do
    :ssl.start()
    :inets.start()

    json_body = Jason.encode!(body)
    url = "#{@base_url}/#{model}:generateContent?key=#{api_key}"

    headers = [
      {~c"content-type", ~c"application/json"}
    ]

    ssl_opts = ssl_options()

    http_opts = [
      timeout: @timeout,
      connect_timeout: 10_000,
      ssl: ssl_opts
    ]

    request = {String.to_charlist(url), headers, ~c"application/json", json_body}

    case :httpc.request(:post, request, http_opts, []) do
      {:ok, {{_, status, _}, _headers, resp_body}} when status in 200..299 ->
        case Jason.decode(:erlang.list_to_binary(resp_body)) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, reason} -> {:error, {:json_parse_error, reason}}
        end

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        body_str = :erlang.list_to_binary(resp_body)
        Logger.error("Gemini API 오류 #{status}: #{body_str}")

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
        Logger.error("Gemini HTTP 요청 실패: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp ssl_options do
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
