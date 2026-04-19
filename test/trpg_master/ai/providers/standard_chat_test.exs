defmodule TrpgMaster.AI.Providers.StandardChatTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Retry
  alias TrpgMaster.AI.Providers.StandardChat

  defmodule FakeResponse do
    def tool_loop?(response), do: Map.get(response, :loop?, false)
    def tool_calls(response), do: Map.get(response, :tool_calls, [])
    def completion_text(response), do: Map.get(response, :text, "")

    def append_tool_results(body, _response, provider_payloads) do
      Map.update(body, :history, [provider_payloads], &(&1 ++ [provider_payloads]))
    end
  end

  test "run/1 returns final text and usage for a standard provider" do
    assert {:ok, result} =
             StandardChat.run(
               provider: "TestProvider",
               body: %{history: []},
               context: %{response: %{loop?: false, text: "완료"}},
               max_tool_iterations: 3,
               call_api: fn %{response: response}, _body -> {:ok, response} end,
               response_module: FakeResponse,
               execute_tools: fn _tool_calls -> {[], []} end,
               usage_info: fn _response, usage ->
                 %{
                   usage: %{
                     input_tokens: usage.input_tokens + 3,
                     output_tokens: usage.output_tokens + 7
                   },
                   log: "test log"
                 }
               end,
               retry_rules: [Retry.rate_limit_rule("TestProvider")],
               retry_opts: [sleep_fun: fn _duration -> :ok end]
             )

    assert result == %{
             text: "완료",
             tool_results: [],
             usage: %{input_tokens: 3, output_tokens: 7}
           }
  end

  test "run/1 executes tools and continues the loop with updated body" do
    Process.put(:standard_chat_call_count, 0)

    on_exit(fn ->
      Process.delete(:standard_chat_call_count)
    end)

    assert {:ok, result} =
             StandardChat.run(
               provider: "TestProvider",
               body: %{history: []},
               context: %{},
               max_tool_iterations: 3,
               call_api: fn _context, body ->
                 call_count = Process.get(:standard_chat_call_count, 0)
                 Process.put(:standard_chat_call_count, call_count + 1)

                 case call_count do
                   0 ->
                     assert body.history == []
                     {:ok, %{loop?: true, tool_calls: [%{name: "inspect"}]}}

                   1 ->
                     assert body.history == [[%{payload: "tool-result"}]]
                     {:ok, %{loop?: false, text: "도구 실행 완료"}}
                 end
               end,
               response_module: FakeResponse,
               execute_tools: fn [%{name: "inspect"}] ->
                 {[%{tool: "inspect", result: %{"status" => "ok"}}], [%{payload: "tool-result"}]}
               end,
               usage_info: fn _response, usage ->
                 %{
                   usage: %{
                     input_tokens: usage.input_tokens + 1,
                     output_tokens: usage.output_tokens + 2
                   },
                   log: "tool loop"
                 }
               end,
               retry_rules: [Retry.rate_limit_rule("TestProvider")],
               retry_opts: [sleep_fun: fn _duration -> :ok end]
             )

    assert Process.get(:standard_chat_call_count) == 2

    assert result == %{
             text: "도구 실행 완료",
             tool_results: [%{tool: "inspect", result: %{"status" => "ok"}}],
             usage: %{input_tokens: 2, output_tokens: 4}
           }
  end

  test "run/1 retries with transformed state when retry rules match" do
    Process.put(:standard_chat_retry_bodies, [])

    on_exit(fn ->
      Process.delete(:standard_chat_retry_bodies)
    end)

    assert {:ok, result} =
             StandardChat.run(
               provider: "TestProvider",
               body: %{retried?: false},
               context: %{},
               max_tool_iterations: 3,
               call_api: fn _context, body ->
                 Process.put(
                   :standard_chat_retry_bodies,
                   Process.get(:standard_chat_retry_bodies, []) ++ [body]
                 )

                 if body.retried? do
                   {:ok, %{loop?: false, text: "재시도 성공"}}
                 else
                   {:error, {:api_error, 429, %{}}}
                 end
               end,
               response_module: FakeResponse,
               execute_tools: fn _tool_calls -> {[], []} end,
               usage_info: fn _response, usage ->
                 %{usage: usage, log: "retry test"}
               end,
               retry_rules: [
                 Retry.status_rule(429, 1,
                   log: fn _attempt, _reason -> "retry" end,
                   transform: fn state, _reason ->
                     %{state | body: %{state.body | retried?: true}}
                   end
                 )
               ],
               retry_opts: [sleep_fun: fn _duration -> :ok end]
             )

    assert Process.get(:standard_chat_retry_bodies) == [%{retried?: false}, %{retried?: true}]
    assert result.text == "재시도 성공"
  end

  test "run/1 preserves accumulated tool results and usage across retry" do
    Process.put(:standard_chat_retry_sequence, 0)

    on_exit(fn ->
      Process.delete(:standard_chat_retry_sequence)
    end)

    assert {:ok, result} =
             StandardChat.run(
               provider: "TestProvider",
               body: %{history: [], retried?: false},
               context: %{},
               max_tool_iterations: 4,
               call_api: fn _context, body ->
                 step = Process.get(:standard_chat_retry_sequence, 0)
                 Process.put(:standard_chat_retry_sequence, step + 1)

                 case step do
                   0 ->
                     assert body.history == []
                     {:ok, %{loop?: true, tool_calls: [%{name: "inspect"}]}}

                   1 ->
                     assert body.history == [[%{payload: "tool-result"}]]
                     {:error, {:api_error, 429, %{}}}

                   2 ->
                     assert body.retried?
                     assert body.history == [[%{payload: "tool-result"}]]
                     {:ok, %{loop?: false, text: "재시도 후 완료"}}
                 end
               end,
               response_module: FakeResponse,
               execute_tools: fn [%{name: "inspect"}] ->
                 {[%{tool: "inspect", result: %{"status" => "ok"}}], [%{payload: "tool-result"}]}
               end,
               usage_info: fn _response, usage ->
                 %{
                   usage: %{
                     input_tokens: usage.input_tokens + 1,
                     output_tokens: usage.output_tokens + 2
                   },
                   log: "preserve state"
                 }
               end,
               retry_rules: [
                 Retry.status_rule(429, 1,
                   log: fn _attempt, _reason -> "retry" end,
                   transform: fn state, _reason ->
                     %{state | body: %{state.body | retried?: true}}
                   end
                 )
               ],
               retry_opts: [sleep_fun: fn _duration -> :ok end]
             )

    assert result == %{
             text: "재시도 후 완료",
             tool_results: [%{tool: "inspect", result: %{"status" => "ok"}}],
             usage: %{input_tokens: 2, output_tokens: 4}
           }
  end
end
