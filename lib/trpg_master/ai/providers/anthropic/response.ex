defmodule TrpgMaster.AI.Providers.Anthropic.Response do
  @moduledoc false

  @tool_result_note "[시스템] 위 assistant 메시지의 text 부분은 플레이어에게 전달되지 않았습니다. " <>
                      "최종 응답에 도구 호출 전에 작성했던 서술 내용을 자연스럽게 포함하여 완전한 장면을 작성하세요."

  def tool_loop?(response) do
    Map.get(response, "stop_reason") == "tool_use" && tool_calls(response) != []
  end

  def tool_calls(response) do
    response
    |> content()
    |> Enum.filter(&(&1["type"] == "tool_use"))
  end

  def completion_text(response) do
    response
    |> text_parts()
    |> Enum.join("\n")
  end

  def append_tool_results(body, response, tool_result_blocks) do
    updated_messages =
      body.messages ++
        [
          %{role: "assistant", content: content(response)},
          %{role: "user", content: user_content(response, tool_result_blocks)}
        ]

    %{body | messages: updated_messages}
  end

  defp user_content(response, tool_result_blocks) do
    if Enum.any?(text_parts(response), &(String.trim(&1) != "")) do
      tool_result_blocks ++ [%{type: "text", text: @tool_result_note}]
    else
      tool_result_blocks
    end
  end

  defp content(response) do
    Map.get(response, "content", [])
  end

  defp text_parts(response) do
    response
    |> content()
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
  end
end
