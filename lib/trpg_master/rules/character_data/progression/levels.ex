defmodule TrpgMaster.Rules.CharacterData.Progression.Levels do
  @moduledoc false

  @xp_thresholds [
    {1, 0},
    {2, 300},
    {3, 900},
    {4, 2_700},
    {5, 6_500},
    {6, 14_000},
    {7, 23_000},
    {8, 34_000},
    {9, 48_000},
    {10, 64_000},
    {11, 85_000},
    {12, 100_000},
    {13, 120_000},
    {14, 140_000},
    {15, 165_000},
    {16, 195_000},
    {17, 225_000},
    {18, 265_000},
    {19, 305_000},
    {20, 355_000}
  ]

  @asi_levels %{
    "default" => [4, 8, 12, 16, 19],
    "fighter" => [4, 6, 8, 12, 14, 16, 19],
    "rogue" => [4, 8, 10, 12, 16, 19]
  }

  @subclass_levels %{
    "default" => [3],
    "barbarian" => [3],
    "bard" => [3],
    "cleric" => [3],
    "druid" => [3],
    "fighter" => [3],
    "monk" => [3],
    "paladin" => [3],
    "ranger" => [3],
    "rogue" => [3],
    "sorcerer" => [3],
    "warlock" => [3],
    "wizard" => [3]
  }

  def level_for_xp(xp) when is_integer(xp) do
    @xp_thresholds
    |> Enum.filter(fn {_level, required} -> xp >= required end)
    |> List.last()
    |> elem(0)
  end

  def level_for_xp(_), do: 1

  def xp_for_level(level) when level in 1..20 do
    {^level, xp} = List.keyfind!(@xp_thresholds, level, 0)
    xp
  end

  def xp_for_level(_), do: 0

  def proficiency_bonus_for_level(level) when is_integer(level) do
    cond do
      level >= 17 -> 6
      level >= 13 -> 5
      level >= 9 -> 4
      level >= 5 -> 3
      true -> 2
    end
  end

  def proficiency_bonus_for_level(_), do: 2

  def asi_level?(level, class_id \\ nil) do
    levels = Map.get(@asi_levels, class_id, @asi_levels["default"])
    level in levels
  end

  def subclass_level?(level, class_id \\ nil) do
    levels = Map.get(@subclass_levels, class_id, @subclass_levels["default"])
    level in levels
  end
end
