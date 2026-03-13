defmodule TrpgMaster.AI.Client do
  @moduledoc """
  Claude API 호출 + tool use 루프.
  Erlang :httpc를 사용하여 외부 HTTP 의존성 없이 구현.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @max_tool_iterations 10
  @timeout 120_000

  @doc """
  Claude API에 메시지를 보내고 응답을 받는다.
  tool use가 발생하면 도구를 실행하고 자동으로 재호출한다.

  반환값:
    {:ok, %{text: String.t(), tool_results: [map()], usage: map()}}
    {:error, term()}
  """
  def chat(system_prompt, messages, tools \\ []) do
    api_key = Application.get_env(:trpg_master, :anthropic_api_key)

    if is_nil(api_key) || api_key == "" do
      {:error, "ANTHROPIC_API_KEY가 설정되지 않았습니다"}
    else
      body = %{
        model: model(),
        max_tokens: 4096,
        system: system_prompt,
        messages: messages,
        tools: tools
      }

      do_chat_loop(api_key, body, [], @max_tool_iterations, %{
        input_tokens: 0,
        output_tokens: 0
      })
    end
  end

  defp do_chat_loop(_api_key, _body, _tool_results, 0, _usage) do
    Logger.warning("Tool use 최대 반복 횟수 초과")
    {:error, "도구 사용 반복 횟수 초과 (#{@max_tool_iterations}회)"}
  end

  defp do_chat_loop(api_key, body, tool_results, iterations_left, usage) do
    case call_api(api_key, body) do
      {:ok, response} ->
        new_usage = %{
          input_tokens: usage.input_tokens + get_in(response, ["usage", "input_tokens"]) || 0,
          output_tokens: usage.output_tokens + get_in(response, ["usage", "output_tokens"]) || 0
        }

        Logger.info(
          "Claude API 호출 — 입력: #{get_in(response, ["usage", "input_tokens"])}토큰, 출력: #{get_in(response, ["usage", "output_tokens"])}토큰"
        )

        handle_response(api_key, body, response, tool_results, iterations_left, new_usage)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp handle_response(api_key, body, response, tool_results, iterations_left, usage) do
    content = Map.get(response, "content", [])
    stop_reason = Map.get(response, "stop_reason")

    # Extract text blocks and tool_use blocks
    text_parts =
      content
      |> Enum.filter(&(&1["type"] == "text"))
      |> Enum.map(& &1["text"])

    tool_use_blocks =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))

    if stop_reason == "tool_use" && length(tool_use_blocks) > 0 do
      # Execute tools and continue the loop
      {new_tool_results, tool_result_blocks} = execute_tools(tool_use_blocks)

      # Add assistant message (with tool_use) and user message (with tool_results)
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
      # Final response — no more tool use
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

  defp call_api(api_key, body) do
    # Ensure :ssl and :inets are started
    :ssl.start()
    :inets.start()

    json_body = Jason.encode!(body)

    headers = [
      {~c"x-api-key", String.to_charlist(api_key)},
      {~c"anthropic-version", ~c"2023-06-01"},
      {~c"content-type", ~c"application/json"}
    ]

    # Configure SSL with system CA certs
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
          {:error, reason} -> {:error, "JSON 파싱 오류: #{inspect(reason)}"}
        end

      {:ok, {{_, status, _}, _headers, resp_body}} ->
        body_str = :erlang.list_to_binary(resp_body)
        Logger.error("Claude API 오류 #{status}: #{body_str}")
        {:error, "API 오류 (#{status}): #{String.slice(body_str, 0, 200)}"}

      {:error, reason} ->
        Logger.error("HTTP 요청 실패: #{inspect(reason)}")
        {:error, "HTTP 요청 실패: #{inspect(reason)}"}
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
end
