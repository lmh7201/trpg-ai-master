defmodule TrpgMaster.AI.ToolExecutor.Lookup.Compactor do
  @moduledoc false

  def compact(:class, entry) do
    Map.take(entry, [
      "id",
      "name",
      "description",
      "primaryAbility",
      "hitPointDie",
      "savingThrowProficiencies",
      "skillProficiencies",
      "weaponProficiencies",
      "armorTraining",
      "startingEquipment",
      "becomingThisClass",
      "classTableGroups",
      "levelFeatures"
    ])
    |> flatten_ko()
  end

  def compact(:monster, entry) do
    Map.take(entry, [
      "id",
      "name",
      "size",
      "type",
      "ac",
      "hp",
      "speed",
      "abilities",
      "cr",
      "xp",
      "traits",
      "actions",
      "bonusActions",
      "reactions",
      "legendaryActions",
      "legendaryActionsDesc",
      "immunities",
      "resistances",
      "conditionImmunities",
      "senses",
      "languages",
      "skillProficiencies"
    ])
    |> flatten_ko()
  end

  def compact(:rule, %{"sections" => sections} = entry) when is_list(sections) do
    compact_sections =
      Enum.map(sections, fn section ->
        Map.take(section, ["id", "title", "content"])
        |> Map.update("content", [], fn content ->
          if is_list(content) do
            Enum.map(content, fn item ->
              if is_map(item) do
                case Map.get(item, "content") do
                  sub_content when is_list(sub_content) and length(sub_content) > 3 ->
                    Map.put(
                      item,
                      "content",
                      Enum.take(sub_content, 3) ++ [%{"type" => "text", "text" => "...(이하 생략)"}]
                    )

                  _ ->
                    item
                end
              else
                item
              end
            end)
          else
            content
          end
        end)
      end)

    Map.put(entry, "sections", compact_sections)
    |> flatten_ko()
  end

  def compact(:spell, entry) when is_map(entry) do
    result =
      entry
      |> Map.drop(["source"])
      |> maybe_drop_empty("castingTimeDetails")
      |> maybe_drop_false("isRitual")
      |> maybe_drop_false("concentration")

    result =
      case result["level"] do
        0 -> Map.put(result, "note", "이 주문은 소마법(cantrip)입니다. 주문 슬롯을 소모하지 않습니다.")
        _ -> result
      end

    flatten_ko(result)
  end

  def compact(:item, entry) do
    entry
    |> Map.drop(["source"])
    |> flatten_ko()
  end

  def compact(_type, entry), do: flatten_ko(entry)

  def flatten_ko(%{"ko" => ko, "en" => _} = map) when map_size(map) == 2, do: ko
  def flatten_ko(%{"ko" => ko} = map) when map_size(map) == 1, do: ko
  def flatten_ko(%{"en" => en} = map) when map_size(map) == 1, do: en

  def flatten_ko(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, flatten_ko(value)} end)
  end

  def flatten_ko(list) when is_list(list) do
    Enum.map(list, &flatten_ko/1)
  end

  def flatten_ko(other), do: other

  defp maybe_drop_empty(map, key) do
    case Map.get(map, key) do
      %{"ko" => "", "en" => ""} -> Map.delete(map, key)
      "" -> Map.delete(map, key)
      nil -> Map.delete(map, key)
      _ -> map
    end
  end

  defp maybe_drop_false(map, key) do
    if Map.get(map, key) == false, do: Map.delete(map, key), else: map
  end
end
