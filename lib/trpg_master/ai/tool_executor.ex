defmodule TrpgMaster.AI.ToolExecutor do
  @moduledoc false

  alias TrpgMaster.AI.ToolExecutor.{Dice, Lookup, State}

  def execute("roll_dice", input), do: Dice.execute(input)
  def execute("lookup_spell", input), do: Lookup.lookup_spell(input)
  def execute("lookup_monster", input), do: Lookup.lookup_monster(input)
  def execute("search_monsters", input), do: Lookup.search_monsters(input)
  def execute("lookup_class", input), do: Lookup.lookup_class(input)
  def execute("lookup_item", input), do: Lookup.lookup_item(input)
  def execute("consult_oracle", input), do: Lookup.consult_oracle(input)
  def execute("list_oracles", _input), do: Lookup.list_oracles()
  def execute("lookup_rule", input), do: Lookup.lookup_rule(input)
  def execute("lookup_dc", input), do: Lookup.lookup_dc(input)
  def execute("get_character_info", input), do: State.get_character_info(input)
  def execute("update_character", input), do: State.update_character(input)
  def execute("register_npc", input), do: State.register_npc(input)
  def execute("update_quest", input), do: State.update_quest(input)
  def execute("set_location", input), do: State.set_location(input)
  def execute("start_combat", input), do: State.start_combat(input)
  def execute("end_combat", input), do: State.end_combat(input)
  def execute("level_up", input), do: State.level_up(input)
  def execute("write_journal", input), do: State.write_journal(input)
  def execute("read_journal", input), do: State.read_journal(input)

  def execute(tool_name, _input) do
    {:error, "알 수 없는 도구: #{tool_name}"}
  end
end
