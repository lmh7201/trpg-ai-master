defmodule TrpgMaster.Rules.CharacterData.Progression.Features do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  def class_features_for_level(class_id, level)
      when is_binary(class_id) and is_integer(level) do
    CharacterData.class_features()
    |> features_for_level(class_id, level)
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

  def subclass_features_for_level(subclass_id, level)
      when is_binary(subclass_id) and is_integer(level) do
    CharacterData.subclass_features()
    |> features_for_level(subclass_id, level)
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

  defp features_for_level(feature_map, id, level)
       when is_map(feature_map) and map_size(feature_map) > 0 do
    case Map.get(feature_map, id) do
      features when is_list(features) ->
        features
        |> Enum.filter(fn feature -> feature["level"] == level end)
        |> Enum.map(&feature_name/1)
        |> Enum.reject(&(&1 == ""))

      _ ->
        []
    end
  end

  defp features_for_level(_, _id, _level), do: []

  defp feature_name(feature) do
    ko = get_in(feature, ["name", "ko"]) || ""
    en = get_in(feature, ["name", "en"]) || ""
    if en != "" && ko != en, do: "#{ko} (#{en})", else: ko
  end
end
