defmodule TrpgMaster.AI.Providers.OpenAI.Request do
  @moduledoc false

  def build(system_prompt, messages, tools, opts) do
    model = Keyword.get(opts, :model, "gpt-4.1")
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    body = %{
      model: model,
      max_completion_tokens: max_tokens,
      messages: convert_messages(system_prompt, messages)
    }

    maybe_add_tools(body, convert_tools(tools))
  end

  # Claude 형식의 메시지를 OpenAI 형식으로 변환
  # system_prompt는 system 메시지로 앞에 추가
  defp convert_messages(system_prompt, messages) do
    system_msg = %{role: "system", content: system_prompt}

    user_messages =
      Enum.flat_map(messages, fn msg ->
        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]

        case {role, content} do
          {"user", content} when is_binary(content) ->
            [%{role: "user", content: content}]

          {"assistant", content} when is_binary(content) ->
            [%{role: "assistant", content: content}]

          {"user", content} when is_list(content) ->
            Enum.map(content, fn block ->
              %{
                role: "tool",
                tool_call_id: block[:tool_use_id] || block["tool_use_id"],
                content: block[:content] || block["content"] || ""
              }
            end)

          {"assistant", content} when is_list(content) ->
            text_parts = Enum.filter(content, &((&1["type"] || &1[:type]) == "text"))
            tool_use_parts = Enum.filter(content, &((&1["type"] || &1[:type]) == "tool_use"))

            text =
              text_parts
              |> Enum.map(&(&1["text"] || &1[:text] || ""))
              |> Enum.join("\n")

            tool_calls =
              Enum.map(tool_use_parts, fn tool_use ->
                %{
                  id: tool_use["id"] || tool_use[:id],
                  type: "function",
                  function: %{
                    name: tool_use["name"] || tool_use[:name],
                    arguments: Jason.encode!(tool_use["input"] || tool_use[:input] || %{})
                  }
                }
              end)

            build_assistant_message(text, tool_calls)

          _ ->
            []
        end
      end)

    [system_msg | user_messages]
  end

  defp build_assistant_message(text, tool_calls) do
    msg = %{role: "assistant"}
    msg = if text != "", do: Map.put(msg, :content, text), else: msg
    msg = if tool_calls != [], do: Map.put(msg, :tool_calls, tool_calls), else: msg
    [msg]
  end

  defp convert_tools([]), do: []

  defp convert_tools(tools) do
    Enum.map(tools, fn tool ->
      name = tool[:name] || tool["name"]
      description = tool[:description] || tool["description"]
      input_schema = tool[:input_schema] || tool["input_schema"] || %{}

      %{
        type: "function",
        function: %{
          name: name,
          description: description,
          parameters: input_schema
        }
      }
    end)
  end

  defp maybe_add_tools(body, []), do: body
  defp maybe_add_tools(body, tools), do: Map.put(body, :tools, tools)
end
