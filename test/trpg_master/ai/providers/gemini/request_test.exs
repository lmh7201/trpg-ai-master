defmodule TrpgMaster.AI.Providers.Gemini.RequestTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Gemini.Request

  test "build/4 converts messages and sanitizes unsupported schema fields" do
    messages = [
      %{"role" => "assistant", "content" => "장면을 정리합니다."},
      %{
        "role" => "user",
        "content" => [
          %{
            "type" => "tool_result",
            "tool_use_id" => "lookup_rule",
            "content" => "{\"ok\":true}"
          },
          %{"type" => "text", "text" => "이어서 설명해줘"}
        ]
      }
    ]

    tools = [
      %{
        "name" => "lookup_rule",
        "description" => "규칙 조회",
        "input_schema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "properties" => %{
            "query" => %{"type" => "string", "additionalProperties" => false}
          }
        }
      }
    ]

    body = Request.build("system prompt", messages, tools, max_tokens: 222)

    assert body.generation_config.max_output_tokens == 222
    assert body.system_instruction == %{parts: [%{text: "system prompt"}]}
    assert hd(body.contents) == %{role: "model", parts: [%{text: "장면을 정리합니다."}]}

    assert Enum.at(body.contents, 1).parts |> hd() |> get_in([:function_response, :name]) ==
             "lookup_rule"

    refute Map.has_key?(
             hd(body.tools).function_declarations |> hd() |> Map.get(:parameters),
             "additionalProperties"
           )
  end
end
