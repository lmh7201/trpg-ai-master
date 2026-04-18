defmodule TrpgMaster.AI.ToolExecutor.Lookup do
  @moduledoc false

  alias TrpgMaster.Oracle.Loader, as: OracleLoader
  alias TrpgMaster.Rules.DC, as: DCLoader
  alias TrpgMaster.Rules.Loader, as: RulesLoader

  def lookup_spell(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:spell, name)
  end

  def lookup_monster(input) do
    name = Map.get(input, "name", "")
    lookup_monsters_list(name)
  end

  def search_monsters(input) do
    cr_min = Map.get(input, "cr_min")
    cr_max = Map.get(input, "cr_max")
    tags = Map.get(input, "tags", [])
    type_filter = Map.get(input, "type")
    limit = min(Map.get(input, "limit", 10), 30)

    all_monsters = RulesLoader.list(:monster)

    results =
      all_monsters
      |> Enum.filter(fn monster -> matches_cr(monster, cr_min, cr_max) end)
      |> Enum.filter(fn monster -> matches_tags(monster, tags) end)
      |> Enum.filter(fn monster -> matches_type(monster, type_filter) end)
      |> Enum.take(limit)
      |> Enum.map(fn monster ->
        %{
          "name" => get_in(monster, ["name", "ko"]) || get_in(monster, ["name", "en"]),
          "nameEn" => get_in(monster, ["name", "en"]),
          "cr" => Map.get(monster, "cr"),
          "size" => get_in(monster, ["size", "ko"]) || get_in(monster, ["size", "en"]),
          "type" => get_in(monster, ["type", "ko"]) || get_in(monster, ["type", "en"]),
          "tags" => Map.get(monster, "tags", [])
        }
      end)

    {:ok,
     %{
       "count" => length(results),
       "monsters" => results,
       "tip" => "상세 스탯은 lookup_monster(name)으로 조회하세요."
     }}
  end

  def lookup_class(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:class, name)
  end

  def lookup_item(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:item, name)
  end

  def consult_oracle(input) do
    oracle_name = Map.get(input, "oracle_name", "")
    question = Map.get(input, "question")

    case OracleLoader.random_result(oracle_name) do
      {:ok, result} ->
        response = %{"oracle" => oracle_name, "result" => result}
        response = if question, do: Map.put(response, "question", question), else: response
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_oracles do
    oracles =
      OracleLoader.list()
      |> Enum.map(fn oracle ->
        meta = oracle["metadata"] || %{}

        %{
          "name" => meta["name"],
          "name_ko" => meta["name_ko"],
          "description" => meta["description"],
          "category" => meta["category"]
        }
      end)
      |> Enum.sort_by(& &1["name"])

    {:ok, %{"oracles" => oracles}}
  end

  def lookup_rule(input) do
    query = Map.get(input, "query", "")
    category = Map.get(input, "category")

    if category do
      case RulesLoader.lookup(:rule, category) do
        {:ok, entry} -> {:ok, entry}
        :not_found -> lookup_compacted(:rule, query)
      end
    else
      lookup_compacted(:rule, query)
    end
  end

  def lookup_dc(input) do
    skill_or_attribute = Map.get(input, "skill_or_attribute", "")
    result = DCLoader.lookup(skill_or_attribute)
    context = Map.get(input, "context")
    result = if context, do: Map.put(result, "context", context), else: result
    {:ok, result}
  end

  defp lookup_compacted(type, name) do
    result =
      case RulesLoader.lookup(type, name) do
        {:ok, entry} ->
          {:ok, entry}

        :not_found ->
          case RulesLoader.search(type, name) do
            [first | _] -> {:ok, first}
            [] -> {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}
          end
      end

    case result do
      {:ok, entry} when is_map(entry) -> {:ok, compact_entry(type, entry)}
      other -> other
    end
  end

  defp lookup_monsters_list(name) do
    case RulesLoader.lookup(:monster, name) do
      {:ok, entry} ->
        {:ok, %{"count" => 1, "monsters" => [compact_entry(:monster, entry)]}}

      :not_found ->
        case RulesLoader.search(:monster, name) do
          [] ->
            {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}

          entries ->
            compacted = Enum.map(entries, &compact_entry(:monster, &1))
            {:ok, %{"count" => length(compacted), "monsters" => compacted}}
        end
    end
  end

  defp compact_entry(:class, entry) do
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

  defp compact_entry(:monster, entry) do
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

  defp compact_entry(:rule, %{"sections" => sections} = entry) when is_list(sections) do
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

  defp compact_entry(:spell, entry) when is_map(entry) do
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

  defp compact_entry(:item, entry) do
    entry
    |> Map.drop(["source"])
    |> flatten_ko()
  end

  defp compact_entry(_type, entry), do: flatten_ko(entry)

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

  defp flatten_ko(%{"ko" => ko, "en" => _} = map) when map_size(map) == 2, do: ko
  defp flatten_ko(%{"ko" => ko} = map) when map_size(map) == 1, do: ko
  defp flatten_ko(%{"en" => en} = map) when map_size(map) == 1, do: en

  defp flatten_ko(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, flatten_ko(value)} end)
  end

  defp flatten_ko(list) when is_list(list) do
    Enum.map(list, &flatten_ko/1)
  end

  defp flatten_ko(other), do: other

  defp matches_cr(_monster, nil, nil), do: true

  defp matches_cr(monster, cr_min, cr_max) do
    cr_val = RulesLoader.parse_cr(Map.get(monster, "cr", ""))

    case cr_val do
      nil ->
        false

      value ->
        above_min = is_nil(cr_min) || value >= cr_min
        below_max = is_nil(cr_max) || value <= cr_max
        above_min && below_max
    end
  end

  defp matches_tags(_monster, []), do: true

  defp matches_tags(monster, tags) do
    monster_tags = Map.get(monster, "tags", [])

    Enum.all?(tags, fn tag ->
      Enum.member?(monster_tags, String.downcase(tag))
    end)
  end

  defp matches_type(_monster, nil), do: true

  defp matches_type(monster, type_filter) do
    type_val = Map.get(monster, "type")

    monster_type =
      cond do
        is_map(type_val) -> (type_val["en"] || "") |> String.downcase()
        is_binary(type_val) -> String.downcase(type_val)
        true -> ""
      end

    String.contains?(monster_type, String.downcase(type_filter))
  end
end
