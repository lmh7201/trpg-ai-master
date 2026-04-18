defmodule TrpgMaster.AI.Providers.Gemini.Response do
  @moduledoc false

  def tool_loop?(response) do
    tool_calls(response) != []
  end

  def tool_calls(response) do
    response
    |> parts()
    |> Enum.filter(&Map.has_key?(&1, "functionCall"))
  end

  def completion_text(response) do
    response
    |> text_parts()
    |> Enum.join("\n")
  end

  def append_tool_results(body, response, function_responses) do
    model_turn = %{
      role: "model",
      parts: parts(response)
    }

    user_turn = %{
      role: "user",
      parts: function_responses
    }

    %{body | contents: body.contents ++ [model_turn, user_turn]}
  end

  defp parts(response) do
    get_in(response, ["candidates", Access.at(0), "content", "parts"]) || []
  end

  defp text_parts(response) do
    response
    |> parts()
    |> Enum.filter(&Map.has_key?(&1, "text"))
    |> Enum.map(& &1["text"])
  end
end
