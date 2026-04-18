defmodule TrpgMaster.AI.Providers.OpenAI.RequestTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.OpenAI.Request

  test "build/4 converts claude-style tool messages into openai request format" do
    messages = [
      %{
        "role" => "assistant",
        "content" => [
          %{"type" => "text", "text" => "먼저 확인해볼게요."},
          %{
            "type" => "tool_use",
            "id" => "tool-1",
            "name" => "lookup_rule",
            "input" => %{"query" => "기절"}
          }
        ]
      },
      %{
        "role" => "user",
        "content" => [
          %{"type" => "tool_result", "tool_use_id" => "tool-1", "content" => "{\"ok\":true}"}
        ]
      }
    ]

    tools = [
      %{
        name: "lookup_rule",
        description: "규칙 조회",
        input_schema: %{"type" => "object"}
      }
    ]

    body = Request.build("system prompt", messages, tools, model: "gpt-4.1-mini", max_tokens: 123)

    assert body.model == "gpt-4.1-mini"
    assert body.max_completion_tokens == 123
    assert hd(body.messages) == %{role: "system", content: "system prompt"}

    assert Enum.at(body.messages, 1).tool_calls |> hd() |> get_in([:function, :name]) ==
             "lookup_rule"

    assert Enum.at(body.messages, 2) == %{
             role: "tool",
             tool_call_id: "tool-1",
             content: "{\"ok\":true}"
           }

    assert hd(body.tools).function.name == "lookup_rule"
  end
end
