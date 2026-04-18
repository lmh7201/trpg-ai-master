defmodule TrpgMaster.Rules.CharacterData.Progression do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

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

  def class_features_for_level(class_id, level)
      when is_binary(class_id) and is_integer(level) do
    github_features = CharacterData.class_features()

    if is_map(github_features) && map_size(github_features) > 0 do
      case Map.get(github_features, class_id) do
        features when is_list(features) ->
          features
          |> Enum.filter(fn feature -> feature["level"] == level end)
          |> Enum.map(&feature_name/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end
    else
      []
    end
  end

  def class_features_for_level(_, _), do: []

  def class_features_for_levels(class_id, from_level, to_level)
      when is_binary(class_id) and is_integer(from_level) and is_integer(to_level) do
    Enum.flat_map(from_level..to_level, fn level ->
      class_features_for_level(class_id, level)
      |> Enum.map(fn name -> %{"name" => name, "level" => level} end)
    end)
  end

  def class_features_for_levels(_, _, _), do: []

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

  def parse_hit_die(nil), do: 8

  def parse_hit_die(str) when is_binary(str) do
    case Regex.run(~r/[Dd](\d+)/, str) do
      [_, num] -> String.to_integer(num)
      _ -> 8
    end
  end

  def asi_level?(level, class_id \\ nil) do
    levels = Map.get(@asi_levels, class_id, @asi_levels["default"])
    level in levels
  end

  def subclass_level?(level, class_id \\ nil) do
    levels = Map.get(@subclass_levels, class_id, @subclass_levels["default"])
    level in levels
  end

  def subclasses_for_class(class_id) when is_binary(class_id) do
    CharacterData.subclasses()
    |> Enum.filter(fn subclass -> subclass["classId"] == class_id end)
  end

  def subclasses_for_class(_), do: []

  def resolve_subclass_name(class_id, subclass_name)
      when is_binary(subclass_name) and subclass_name != "" do
    name_lower = String.downcase(subclass_name)

    subclasses_for_class(class_id)
    |> Enum.find(fn subclass ->
      ko = get_in(subclass, ["name", "ko"]) || ""
      en = get_in(subclass, ["name", "en"]) || ""
      String.downcase(ko) == name_lower || String.downcase(en) == name_lower
    end)
    |> case do
      nil ->
        subclass_name

      subclass ->
        get_in(subclass, ["name", "ko"]) || get_in(subclass, ["name", "en"]) || subclass_name
    end
  end

  def resolve_subclass_name(_, name), do: name

  def resolve_subclass_id(class_id, subclass_name)
      when is_binary(subclass_name) and subclass_name != "" do
    name_lower = String.downcase(subclass_name)

    subclasses_for_class(class_id)
    |> Enum.find(fn subclass ->
      ko = get_in(subclass, ["name", "ko"]) || ""
      en = get_in(subclass, ["name", "en"]) || ""
      id = subclass["id"] || ""

      String.downcase(ko) == name_lower ||
        String.downcase(en) == name_lower ||
        String.downcase(id) == name_lower
    end)
    |> case do
      nil -> nil
      subclass -> subclass["id"]
    end
  end

  def resolve_subclass_id(_, _), do: nil

  def subclass_features_for_level(subclass_id, level)
      when is_binary(subclass_id) and is_integer(level) do
    github_features = CharacterData.subclass_features()

    if is_map(github_features) && map_size(github_features) > 0 do
      case Map.get(github_features, subclass_id) do
        features when is_list(features) ->
          features
          |> Enum.filter(fn feature -> feature["level"] == level end)
          |> Enum.map(&feature_name/1)
          |> Enum.reject(&(&1 == ""))

        _ ->
          []
      end
    else
      []
    end
  end

  def subclass_features_for_level(_, _), do: []

  def subclass_features_for_levels(subclass_id, from_level, to_level)
      when is_binary(subclass_id) and is_integer(from_level) and is_integer(to_level) do
    Enum.flat_map(from_level..to_level, fn level ->
      subclass_features_for_level(subclass_id, level)
      |> Enum.map(fn name -> %{"name" => name, "level" => level} end)
    end)
  end

  def subclass_features_for_levels(_, _, _), do: []

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

  def ability_modifier(score) when is_integer(score) do
    div(score - 10, 2)
  end

  def ability_modifier(_), do: 0

  defp feature_name(feature) do
    ko = get_in(feature, ["name", "ko"]) || ""
    en = get_in(feature, ["name", "en"]) || ""
    if en != "" && ko != en, do: "#{ko} (#{en})", else: ko
  end

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
