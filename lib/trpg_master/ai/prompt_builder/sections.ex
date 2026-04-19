defmodule TrpgMaster.AI.PromptBuilder.Sections do
  @moduledoc false

  alias TrpgMaster.AI.PromptBuilder.Sections.{Context, Instructions}
  alias TrpgMaster.Campaign.State

  defdelegate build_summary_section(summary), to: Instructions
  defdelegate build_combat_summary_section(summary), to: Instructions
  defdelegate build_post_combat_section(summary), to: Instructions
  defdelegate build_combat_phase_instruction(combat_phase), to: Instructions
  defdelegate state_tools_instruction(), to: Instructions
  defdelegate mode_instruction(mode), to: Instructions

  def build_campaign_context(%State{} = state), do: Context.build_campaign_context(state)
end
