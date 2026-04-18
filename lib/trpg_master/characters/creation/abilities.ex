defmodule TrpgMaster.Characters.Creation.Abilities do
  @moduledoc false

  alias TrpgMaster.Characters.Creation.Definitions

  def final_abilities_map(assigns) do
    Definitions.ability_keys()
    |> Map.new(fn key -> {key, final_ability_score(assigns, key)} end)
  end

  def final_ability_score(assigns, key) do
    abilities = Map.get(assigns, :abilities, %{})
    bonus_ones = Map.get(assigns, :bg_ability_1, [])

    base = Map.get(abilities, key) || 10
    base = if Map.get(assigns, :bg_ability_2) == key, do: base + 2, else: base

    if key in bonus_ones, do: base + 1, else: base
  end
end
