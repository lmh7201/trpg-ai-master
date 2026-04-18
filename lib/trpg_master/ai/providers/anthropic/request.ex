defmodule TrpgMaster.AI.Providers.Anthropic.Request do
  @moduledoc false

  def build(system_prompt, messages, tools, opts) do
    %{
      model: Keyword.get(opts, :model, default_model()),
      max_tokens: Keyword.get(opts, :max_tokens, 4096),
      system: system_blocks(system_prompt),
      messages: messages,
      tools: add_cache_control_to_tools(tools)
    }
  end

  defp system_blocks(system_prompt) do
    [%{type: "text", text: system_prompt, cache_control: %{type: "ephemeral"}}]
  end

  defp add_cache_control_to_tools([]), do: []

  defp add_cache_control_to_tools(tools) when is_list(tools) do
    {last, rest} = List.pop_at(tools, -1)

    if Map.has_key?(last, :cache_control) || Map.has_key?(last, "cache_control") do
      tools
    else
      rest ++ [Map.put(last, :cache_control, %{type: "ephemeral"})]
    end
  end

  defp default_model do
    Application.get_env(:trpg_master, :ai_model, "claude-sonnet-4-6")
  end
end
