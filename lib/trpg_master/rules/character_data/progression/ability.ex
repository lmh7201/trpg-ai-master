defmodule TrpgMaster.Rules.CharacterData.Progression.Ability do
  @moduledoc false

  def parse_hit_die(nil), do: 8

  def parse_hit_die(str) when is_binary(str) do
    case Regex.run(~r/[Dd](\d+)/, str) do
      [_, num] -> String.to_integer(num)
      _ -> 8
    end
  end

  def ability_modifier(score) when is_integer(score) do
    div(score - 10, 2)
  end

  def ability_modifier(_), do: 0
end
