defmodule TrpgMaster.AI.Providers.Gemini.Request do
  @moduledoc false

  def build(system_prompt, messages, tools, opts) do
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    body = %{
      system_instruction: %{parts: [%{text: system_prompt}]},
      contents: convert_messages(messages),
      generation_config: %{max_output_tokens: max_tokens}
    }

    maybe_add_tools(body, convert_tools(tools))
  end

  # Claude/OpenAI 형식의 메시지를 Gemini contents 형식으로 변환
  defp convert_messages(messages) do
    Enum.flat_map(messages, fn msg ->
      role = msg["role"] || msg[:role]
      content = msg["content"] || msg[:content]

      gemini_role = if role == "assistant", do: "model", else: "user"

      case content do
        text when is_binary(text) ->
          [%{role: gemini_role, parts: [%{text: text}]}]

        parts when is_list(parts) ->
          gemini_parts =
            Enum.map(parts, fn part ->
              type = part[:type] || part["type"]

              cond do
                type == "tool_result" ->
                  %{
                    function_response: %{
                      name: part[:tool_use_id] || part["tool_use_id"] || "unknown",
                      response: %{
                        content: part[:content] || part["content"] || ""
                      }
                    }
                  }

                type == "tool_use" ->
                  %{
                    function_call: %{
                      name: part[:name] || part["name"],
                      args: part[:input] || part["input"] || %{}
                    }
                  }

                true ->
                  text_content = part[:text] || part["text"] || ""
                  %{text: text_content}
              end
            end)
            |> Enum.reject(&(&1 == %{text: ""}))

          if gemini_parts == [] do
            []
          else
            [%{role: gemini_role, parts: gemini_parts}]
          end

        _ ->
          []
      end
    end)
  end

  defp convert_tools([]), do: []

  defp convert_tools(tools) do
    function_declarations =
      Enum.map(tools, fn tool ->
        name = tool[:name] || tool["name"]
        description = tool[:description] || tool["description"]
        input_schema = tool[:input_schema] || tool["input_schema"] || %{}

        %{
          name: name,
          description: description,
          parameters: sanitize_schema(input_schema)
        }
      end)

    [%{function_declarations: function_declarations}]
  end

  defp sanitize_schema(schema) when is_map(schema) do
    schema
    |> Map.drop(["additionalProperties", :additionalProperties])
    |> Map.new(fn {key, value} -> {key, sanitize_schema(value)} end)
  end

  defp sanitize_schema(schema) when is_list(schema) do
    Enum.map(schema, &sanitize_schema/1)
  end

  defp sanitize_schema(other), do: other

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)
end
