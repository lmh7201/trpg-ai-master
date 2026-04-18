defmodule TrpgMaster.AI.ToolExecutor.Lookup.Monsters do
  @moduledoc false

  alias TrpgMaster.AI.ToolExecutor.Lookup.Compactor
  alias TrpgMaster.Rules.Loader, as: RulesLoader

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

    results =
      RulesLoader.list(:monster)
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

  defp lookup_monsters_list(name) do
    case RulesLoader.lookup(:monster, name) do
      {:ok, entry} ->
        {:ok, %{"count" => 1, "monsters" => [Compactor.compact(:monster, entry)]}}

      :not_found ->
        case RulesLoader.search(:monster, name) do
          [] ->
            {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}

          entries ->
            compacted = Enum.map(entries, &Compactor.compact(:monster, &1))
            {:ok, %{"count" => length(compacted), "monsters" => compacted}}
        end
    end
  end

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
