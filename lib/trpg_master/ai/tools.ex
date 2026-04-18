defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice
  Phase 2: lookup_spell, lookup_monster, lookup_class, lookup_item
  """

  alias TrpgMaster.AI.{ToolDefinitions, ToolExecutor}

  @doc """
  사용 가능한 tool 목록을 반환한다. phase에 따라 필요한 도구만 포함한다.
  """
  def definitions(phase \\ :exploration), do: ToolDefinitions.definitions(phase)

  @doc """
  상태 변경 도구 정의를 반환한다.
  """
  defdelegate state_tool_definitions(), to: ToolDefinitions

  @doc """
  tool_use 요청을 실행하고 결과를 반환한다.
  """
  defdelegate execute(tool_name, input), to: ToolExecutor
end
