defmodule TrpgMaster.AI.ToolDefinitions.Phase do
  @moduledoc false

  alias TrpgMaster.AI.ToolDefinitions.Phase.{Dice, Lookup, Oracle, Progression}

  def definitions(:combat) do
    [
      Dice.roll_dice(),
      Lookup.lookup_monster(),
      Lookup.lookup_spell(),
      Lookup.lookup_item(),
      Lookup.lookup_rule(),
      Lookup.lookup_dc(),
      Progression.level_up()
    ]
  end

  def definitions(_phase) do
    [
      Dice.roll_dice(),
      Lookup.lookup_spell(),
      Lookup.lookup_monster(),
      Lookup.search_monsters(),
      Lookup.lookup_class(),
      Lookup.lookup_item(),
      Oracle.consult(),
      Oracle.list(),
      Lookup.lookup_dc(),
      Lookup.lookup_rule(),
      Progression.level_up()
    ]
  end
end
