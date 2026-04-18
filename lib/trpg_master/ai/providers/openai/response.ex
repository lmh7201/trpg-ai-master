defmodule TrpgMaster.AI.Providers.OpenAI.Response do
  @moduledoc false

  def tool_loop?(response) do
    choice(response)["finish_reason"] == "tool_calls" && tool_calls(response) != []
  end

  def tool_calls(response) do
    message(response)["tool_calls"] || []
  end

  def completion_text(response) do
    message(response)["content"] || ""
  end

  def append_tool_results(body, response, tool_result_messages) do
    updated_messages = body.messages ++ [message(response) | tool_result_messages]
    %{body | messages: updated_messages}
  end

  defp choice(response) do
    get_in(response, ["choices", Access.at(0)]) || %{}
  end

  defp message(response) do
    choice(response)["message"] || %{}
  end
end
