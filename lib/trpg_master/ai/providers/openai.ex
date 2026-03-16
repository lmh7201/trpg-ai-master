defmodule TrpgMaster.AI.Providers.OpenAI do
  @moduledoc """
  OpenAI Chat Completions API 프로바이더.
  function calling(tool use) 루프와 재시도를 포함한다.
  """

  require Logger

  @api_url "https://api.openai.com/v1/chat/completions"
  @max_tool_iterations 5
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
      model = Keyword.get(opts, :model, "gpt-4.1")
      max_tokens = Keyword.get(opts, :max_tokens, 4096)

      openai_messages = convert_messages(system_prompt, messages)
      openai_tools = convert_tools(tools)

      body =
        %{
          model: model,
          max_tokens: max_tokens,
          messages: openai_messages
        }
        |> maybe_add_tools(openai_tools)

      do_chat_with_retry(api_key, body, [], 0)
    end
  end

  # ── 메시지 변환 ──────────────────────────────────────────────────────────────

  # Claude 형식의 메시지를 OpenAI 형식으로 변환
  # system_prompt는 system 메시지로 앞에 추가
  defp convert_messages(system_prompt, messages) do
    system_msg = %{role: "system", content: system_prompt}

    user_messages =
      Enum.flat_map(messages, fn msg ->
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]

        case {role, content} do
          {"user", content} when is_binary(content) ->
            [%{role: "user", content: content}]

          {"assistant", content} when is_binary(content) ->
            [%{role: "assistant", content: content}]

          # tool_result 블록을 포함한 user 메시지 (tool 호출 결과)
          {"user", content} when is_list(content) ->
            tool_results =
              Enum.map(content, fn block ->
                %{
                  role: "tool",
                  tool_call_id: block[:tool_use_id] || block["tool_use_id"],
                  content: block[:content] || block["content"] || ""
                }
              end)

            tool_results

          # assistant 메시지에 tool_use 블록 포함 (Claude 형식 → OpenAI 변환)
          {"assistant", content} when is_list(content) ->
            text_parts = Enum.filter(content, &((&1["type"] || &1[:type]) == "text"))
            tool_use_parts = Enum.filter(content, &((&1["type"] || &1[:type]) == "tool_use"))

            text =
              text_parts
              |> Enum.map(&(&1["text"] || &1[:text] || ""))
              |> Enum.join("\n")

            tool_calls =
              Enum.map(tool_use_parts, fn tu ->
                %{
                  id: tu["id"] || tu[:id],
                  type: "function",
                  function: %{
                    name: tu["name"] || tu[:name],
                    arguments: Jason.encode!(tu["input"] || tu[:input] || %{})
                  }
                }
              end)

            msg = %{role: "assistant"}
            msg = if text != "", do: Map.put(msg, :content, text), else: msg

            msg =
              if tool_calls != [],
                do: Map.put(msg, :tool_calls, tool_calls),
                else: msg

            [msg]

          _ ->
            []
        end
      end)

    [system_msg | user_messages]
  end

  # ── 도구 변환 ────────────────────────────────────────────────────────────────

  # Claude tool 정의 → OpenAI function 형식 변환
  defp convert_tools([]), do: []

  defp convert_tools(tools) do
    Enum.map(tools, fn tool ->
      name = tool[:name] || tool["name"]
      description = tool[:description] || tool["description"]
      input_schema = tool[:input_schema] || tool["input_schema"] || %{}

      %{
        type: "function",
        function: %{
          name: name,
          description: description,
          parameters: input_schema
        }
      }
    end)
  end

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)

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

  defp handle_api_error(api_key, body, tool_results, {:api_error, 429, _}, retry_count)
       when retry_count < 3 do
    wait_ms = 2000 * (retry_count + 1)
    Logger.warning("OpenAI Rate limit — #{wait_ms}ms 대기 후 재시도 (#{retry_count + 1}/3)")
    Process.sleep(wait_ms)
    do_chat_with_retry(api_key, body, tool_results, retry_count + 1)
  end

  defp handle_api_error(api_key, body, tool_results, {:api_error, status, _}, retry_count)
       when status in [500, 503] and retry_count < 2 do
    Logger.warning("OpenAI 서버 에러 #{status} — 3초 대기 후 재시도 (#{retry_count + 1}/2)")
    Process.sleep(3000)
    do_chat_with_retry(api_key, body, tool_results, retry_count + 1)
  end

  defp handle_api_error(_api_key, _body, _tool_results, {:api_error, 401, _}, _retry_count) do
    {:error, :invalid_api_key}
  end

  defp handle_api_error(_api_key, _body, _tool_results, reason, _retry_count) do
    {:error, reason}
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
    results =
      Enum.map(tool_calls, fn tc ->
        tool_use_id = tc["id"]
        tool_name = get_in(tc, ["function", "name"])

        tool_input =
          case Jason.decode(get_in(tc, ["function", "arguments"]) || "{}") do
            {:ok, parsed} -> parsed
            _ -> %{}
          end

        Logger.info("OpenAI 도구 실행: #{tool_name} — #{inspect(tool_input)}")

        case TrpgMaster.AI.Tools.execute(tool_name, tool_input) do
          {:ok, result} ->
            {%{tool: tool_name, input: tool_input, result: result},
             %{
               role: "tool",
               tool_call_id: tool_use_id,
               content: Jason.encode!(result)
             }}

          {:error, reason} ->
            {%{tool: tool_name, input: tool_input, error: reason},
             %{
               role: "tool",
               tool_call_id: tool_use_id,
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
      {~c"authorization", String.to_charlist("Bearer #{api_key}")},
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
        Logger.error("OpenAI API 오류 #{status}: #{body_str}")

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
        Logger.error("OpenAI HTTP 요청 실패: #{inspect(reason)}")
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
