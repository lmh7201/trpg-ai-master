defmodule TrpgMaster.Rules.CharacterData.Progression.Spellcasting do
  @moduledoc false

  @full_caster_slots %{
    1 => {2, 0, 0, 0, 0, 0, 0, 0, 0},
    2 => {3, 0, 0, 0, 0, 0, 0, 0, 0},
    3 => {4, 2, 0, 0, 0, 0, 0, 0, 0},
    4 => {4, 3, 0, 0, 0, 0, 0, 0, 0},
    5 => {4, 3, 2, 0, 0, 0, 0, 0, 0},
    6 => {4, 3, 3, 0, 0, 0, 0, 0, 0},
    7 => {4, 3, 3, 1, 0, 0, 0, 0, 0},
    8 => {4, 3, 3, 2, 0, 0, 0, 0, 0},
    9 => {4, 3, 3, 3, 1, 0, 0, 0, 0},
    10 => {4, 3, 3, 3, 2, 0, 0, 0, 0},
    11 => {4, 3, 3, 3, 2, 1, 0, 0, 0},
    12 => {4, 3, 3, 3, 2, 1, 0, 0, 0},
    13 => {4, 3, 3, 3, 2, 1, 1, 0, 0},
    14 => {4, 3, 3, 3, 2, 1, 1, 0, 0},
    15 => {4, 3, 3, 3, 2, 1, 1, 1, 0},
    16 => {4, 3, 3, 3, 2, 1, 1, 1, 0},
    17 => {4, 3, 3, 3, 2, 1, 1, 1, 1},
    18 => {4, 3, 3, 3, 3, 1, 1, 1, 1},
    19 => {4, 3, 3, 3, 3, 2, 1, 1, 1},
    20 => {4, 3, 3, 3, 3, 2, 2, 1, 1}
  }

  @half_caster_slots %{
    1 => {2, 0, 0, 0, 0},
    2 => {2, 0, 0, 0, 0},
    3 => {3, 0, 0, 0, 0},
    4 => {3, 0, 0, 0, 0},
    5 => {4, 2, 0, 0, 0},
    6 => {4, 2, 0, 0, 0},
    7 => {4, 3, 0, 0, 0},
    8 => {4, 3, 0, 0, 0},
    9 => {4, 3, 2, 0, 0},
    10 => {4, 3, 2, 0, 0},
    11 => {4, 3, 3, 0, 0},
    12 => {4, 3, 3, 0, 0},
    13 => {4, 3, 3, 1, 0},
    14 => {4, 3, 3, 1, 0},
    15 => {4, 3, 3, 2, 0},
    16 => {4, 3, 3, 2, 0},
    17 => {4, 3, 3, 3, 1},
    18 => {4, 3, 3, 3, 1},
    19 => {4, 3, 3, 3, 2},
    20 => {4, 3, 3, 3, 2}
  }

  @cantrips_known %{
    "bard" => {2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
    "cleric" => {3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5},
    "druid" => {2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
    "sorcerer" => {4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6},
    "warlock" => {2, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4},
    "wizard" => {3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5}
  }

  @spells_known %{
    "bard" => {4, 5, 6, 7, 9, 10, 11, 12, 14, 15, 16, 16, 17, 17, 18, 18, 19, 20, 22, 22},
    "ranger" => {2, 3, 4, 5, 6, 6, 7, 7, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14},
    "sorcerer" => {2, 4, 6, 7, 9, 10, 11, 12, 14, 15, 16, 16, 17, 17, 18, 18, 19, 20, 21, 22},
    "warlock" => {2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15}
  }

  @warlock_pact_slots %{
    1 => {1, 1},
    2 => {2, 1},
    3 => {2, 2},
    4 => {2, 2},
    5 => {2, 3},
    6 => {2, 3},
    7 => {2, 4},
    8 => {2, 4},
    9 => {2, 5},
    10 => {2, 5},
    11 => {3, 5},
    12 => {3, 5},
    13 => {3, 5},
    14 => {3, 5},
    15 => {3, 5},
    16 => {3, 5},
    17 => {4, 5},
    18 => {4, 5},
    19 => {4, 5},
    20 => {4, 5}
  }

  def spell_slots_for_class_level(class_id, level) when is_integer(level) do
    cond do
      class_id in ["bard", "cleric", "druid", "sorcerer", "wizard"] ->
        slots_tuple_to_map(@full_caster_slots[level])

      class_id == "ranger" ->
        slots_tuple_to_map(@half_caster_slots[level])

      class_id == "warlock" ->
        case @warlock_pact_slots[level] do
          {count, slot_level} when count > 0 ->
            %{Integer.to_string(slot_level) => count}

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  def spell_slots_for_class_level(_, _), do: nil

  def cantrips_known_for_class_level(class_id, level)
      when is_binary(class_id) and is_integer(level) and level in 1..20 do
    case @cantrips_known[class_id] do
      nil -> nil
      tuple -> elem(tuple, level - 1)
    end
  end

  def cantrips_known_for_class_level(_, _), do: nil

  def spells_known_for_class_level(class_id, level)
      when is_binary(class_id) and is_integer(level) and level in 1..20 do
    case @spells_known[class_id] do
      nil -> nil
      tuple -> elem(tuple, level - 1)
    end
  end

  def spells_known_for_class_level(_, _), do: nil

  defp slots_tuple_to_map(nil), do: nil

  defp slots_tuple_to_map(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.with_index(1)
    |> Enum.reject(fn {count, _level} -> count == 0 end)
    |> Map.new(fn {count, level} -> {Integer.to_string(level), count} end)
    |> case do
      map when map_size(map) == 0 -> nil
      map -> map
    end
  end
end
