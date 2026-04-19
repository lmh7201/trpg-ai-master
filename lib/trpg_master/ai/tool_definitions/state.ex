defmodule TrpgMaster.AI.ToolDefinitions.State do
  @moduledoc false

  alias TrpgMaster.AI.ToolDefinitions.State.{Character, Combat, World}

  def state_tool_definitions do
    [
      Character.get_info(),
      Character.update(),
      World.register_npc(),
      World.update_quest(),
      World.set_location(),
      Combat.start(),
      Combat.finish(),
      World.write_journal(),
      World.read_journal()
    ]
  end
end
