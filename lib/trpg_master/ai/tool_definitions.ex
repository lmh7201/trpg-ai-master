defmodule TrpgMaster.AI.ToolDefinitions do
  @moduledoc false

  alias TrpgMaster.AI.ToolDefinitions.{Phase, State}

  def definitions(phase \\ :exploration), do: Phase.definitions(phase)
  defdelegate state_tool_definitions(), to: State
end
