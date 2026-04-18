defmodule TrpgMaster.AI.ToolExecutor.Lookup do
  @moduledoc false

  alias TrpgMaster.AI.ToolExecutor.Lookup.{Monsters, Oracles, Reference}

  def lookup_spell(input), do: Reference.lookup_spell(input)
  def lookup_monster(input), do: Monsters.lookup_monster(input)
  def search_monsters(input), do: Monsters.search_monsters(input)
  def lookup_class(input), do: Reference.lookup_class(input)
  def lookup_item(input), do: Reference.lookup_item(input)
  def consult_oracle(input), do: Oracles.consult_oracle(input)
  def list_oracles, do: Oracles.list_oracles()
  def lookup_rule(input), do: Reference.lookup_rule(input)
  def lookup_dc(input), do: Reference.lookup_dc(input)
end
