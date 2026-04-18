defmodule TrpgMaster.AI.Providers.Anthropic.ResponseTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Anthropic.Response

  test "detects tool use and appends tool results with a note for preceding text" do
    response = %{
      "stop_reason" => "tool_use",
      "content" => [
        %{"type" => "text", "text" => "상자를 조심스럽게 연다."},
        %{
          "type" => "tool_use",
          "id" => "tool-1",
          "name" => "inspect_scene",
          "input" => %{"target" => "box"}
        }
      ]
    }

    body = %{messages: [%{role: "user", content: "상자를 연다"}]}

    tool_result_blocks = [
      %{type: "tool_result", tool_use_id: "tool-1", content: ~s({"items":["key"]})}
    ]

    assert Response.tool_loop?(response)

    assert [%{"id" => "tool-1", "name" => "inspect_scene"}] = Response.tool_calls(response)

    assert %{messages: messages} =
             Response.append_tool_results(body, response, tool_result_blocks)

    assert [
             %{role: "user", content: "상자를 연다"},
             %{
               role: "assistant",
               content: [
                 %{"type" => "text", "text" => "상자를 조심스럽게 연다."},
                 %{"type" => "tool_use", "id" => "tool-1"}
               ]
             },
             %{
               role: "user",
               content: [
                 %{type: "tool_result", tool_use_id: "tool-1", content: ~s({"items":["key"]})},
                 %{type: "text"}
               ]
             }
           ] = messages
  end

  test "joins text blocks into completion text" do
    response = %{
      "stop_reason" => "end_turn",
      "content" => [
        %{"type" => "text", "text" => "안개가 걷히며 탑의 문양이 드러난다."},
        %{"type" => "text", "text" => "바닥에는 오래된 발자국이 남아 있다."}
      ]
    }

    refute Response.tool_loop?(response)

    assert Response.completion_text(response) ==
             "안개가 걷히며 탑의 문양이 드러난다.\n바닥에는 오래된 발자국이 남아 있다."
  end
end
