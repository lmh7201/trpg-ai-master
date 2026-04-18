defmodule TrpgMaster.AI.Providers.Gemini.ResponseTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Gemini.Response

  test "detects function calls and appends model and user turns" do
    response = %{
      "candidates" => [
        %{
          "finishReason" => "STOP",
          "content" => %{
            "parts" => [
              %{"text" => "문을 조사한다"},
              %{"functionCall" => %{"name" => "inspect_scene", "args" => %{"target" => "door"}}}
            ]
          }
        }
      ]
    }

    body = %{contents: [%{role: "user", parts: [%{text: "문을 본다"}]}]}

    function_responses = [
      %{
        function_response: %{
          name: "inspect_scene",
          response: %{content: ~s({"clues":["blood"]})}
        }
      }
    ]

    assert Response.tool_loop?(response)

    assert [%{"functionCall" => %{"name" => "inspect_scene", "args" => %{"target" => "door"}}}] =
             Response.tool_calls(response)

    assert %{contents: contents} =
             Response.append_tool_results(body, response, function_responses)

    assert [
             %{role: "user", parts: [%{text: "문을 본다"}]},
             %{
               role: "model",
               parts: [
                 %{"text" => "문을 조사한다"},
                 %{
                   "functionCall" => %{"name" => "inspect_scene", "args" => %{"target" => "door"}}
                 }
               ]
             },
             %{
               role: "user",
               parts: [
                 %{
                   function_response: %{
                     name: "inspect_scene",
                     response: %{content: ~s({"clues":["blood"]})}
                   }
                 }
               ]
             }
           ] = contents
  end

  test "joins text parts into completion text" do
    response = %{
      "candidates" => [
        %{
          "finishReason" => "STOP",
          "content" => %{
            "parts" => [
              %{"text" => "횃불이 벽을 비춘다."},
              %{"text" => "멀리서 물 떨어지는 소리가 들린다."}
            ]
          }
        }
      ]
    }

    refute Response.tool_loop?(response)

    assert Response.completion_text(response) ==
             "횃불이 벽을 비춘다.\n멀리서 물 떨어지는 소리가 들린다."
  end
end
