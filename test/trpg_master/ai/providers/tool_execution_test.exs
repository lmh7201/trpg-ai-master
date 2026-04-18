defmodule TrpgMaster.AI.Providers.ToolExecutionTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.ToolExecution

  test "run/2 returns shared tool results and provider payloads" do
    Process.put(:journal_entries, [
      %{"category" => "plot", "text" => "숨겨진 문양"},
      %{"category" => "combat", "text" => "고블린과의 전투"}
    ])

    on_exit(fn -> Process.delete(:journal_entries) end)

    tool_calls = [
      %{"id" => "call-1", "name" => "read_journal", "input" => %{"category" => "plot"}},
      %{"id" => "call-2", "name" => "nope", "input" => %{}}
    ]

    {tool_results, provider_payloads} =
      ToolExecution.run(tool_calls,
        provider: "TestProvider",
        extract: fn call ->
          %{
            id: call["id"],
            name: call["name"],
            input: call["input"]
          }
        end,
        success: fn extracted, result ->
          %{
            id: extracted.id,
            status: result["status"],
            total: result["total"]
          }
        end,
        error: fn extracted, reason ->
          %{
            id: extracted.id,
            error: reason
          }
        end
      )

    assert [
             %{
               tool: "read_journal",
               input: %{"category" => "plot"},
               result: %{"status" => "ok", "total" => 1}
             },
             %{tool: "nope", input: %{}, error: "알 수 없는 도구: nope"}
           ] = tool_results

    assert [
             %{id: "call-1", status: "ok", total: 1},
             %{id: "call-2", error: "알 수 없는 도구: nope"}
           ] = provider_payloads
  end
end
