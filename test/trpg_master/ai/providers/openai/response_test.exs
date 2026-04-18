defmodule TrpgMaster.AI.Providers.OpenAI.ResponseTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.OpenAI.Response

  test "detects tool call responses and appends tool result messages" do
    response = %{
      "choices" => [
        %{
          "finish_reason" => "tool_calls",
          "message" => %{
            "role" => "assistant",
            "content" => "주변을 살펴본다",
            "tool_calls" => [
              %{
                "id" => "call-1",
                "function" => %{"name" => "roll_dice", "arguments" => ~s({"sides":20})}
              }
            ]
          }
        }
      ]
    }

    body = %{messages: [%{role: "system", content: "sys"}]}
    tool_result_messages = [%{role: "tool", tool_call_id: "call-1", content: ~s({"total":17})}]

    assert Response.tool_loop?(response)
    assert [%{"id" => "call-1"}] = Response.tool_calls(response)

    assert %{messages: messages} =
             Response.append_tool_results(body, response, tool_result_messages)

    assert [
             %{role: "system", content: "sys"},
             %{
               "role" => "assistant",
               "content" => "주변을 살펴본다",
               "tool_calls" => [%{"id" => "call-1", "function" => %{"name" => "roll_dice"}}]
             },
             %{role: "tool", tool_call_id: "call-1", content: ~s({"total":17})}
           ] = messages
  end

  test "returns completion text when tool call loop is finished" do
    response = %{
      "choices" => [
        %{
          "finish_reason" => "stop",
          "message" => %{
            "role" => "assistant",
            "content" => "전투가 끝나고 방 안이 조용해진다."
          }
        }
      ]
    }

    refute Response.tool_loop?(response)
    assert Response.completion_text(response) == "전투가 끝나고 방 안이 조용해진다."
  end
end
