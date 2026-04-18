defmodule TrpgMaster.Campaign.Combat.Dependencies do
  @moduledoc false

  alias TrpgMaster.AI.{Client, PromptBuilder, Tools}
  alias TrpgMaster.Campaign.{Persistence, Summarizer, ToolHandler}

  def build(opts) do
    %{
      build_prompt: Keyword.get(opts, :build_prompt, &default_build_prompt/2),
      build_turn_messages:
        Keyword.get(opts, :build_turn_messages, &default_build_turn_messages/3),
      tools: Keyword.get(opts, :tools, &default_tools/0),
      chat: Keyword.get(opts, :chat, &Client.chat/4),
      apply_tools: Keyword.get(opts, :apply_tools, &ToolHandler.apply_all/2),
      update_context_summary:
        Keyword.get(opts, :update_context_summary, &Summarizer.update_context_summary/1),
      update_combat_history_summary:
        Keyword.get(
          opts,
          :update_combat_history_summary,
          &Summarizer.update_combat_history_summary/1
        ),
      generate_post_combat_summary:
        Keyword.get(
          opts,
          :generate_post_combat_summary,
          &Summarizer.generate_post_combat_summary/1
        ),
      save_async: Keyword.get(opts, :save_async, &Persistence.save_async/1)
    }
  end

  def tool_context(state) do
    %{journal_entries: state.journal_entries, characters: state.characters}
  end

  defp default_build_prompt(state, combat_phase) do
    PromptBuilder.build(state, combat_phase: combat_phase)
  end

  defp default_build_turn_messages(state, message, combat_phase) do
    PromptBuilder.build_turn_messages(state, message, combat_phase: combat_phase)
  end

  defp default_tools do
    Tools.definitions(:combat) ++ Tools.state_tool_definitions()
  end
end
