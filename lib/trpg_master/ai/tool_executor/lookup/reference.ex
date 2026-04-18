defmodule TrpgMaster.AI.ToolExecutor.Lookup.Reference do
  @moduledoc false

  alias TrpgMaster.AI.ToolExecutor.Lookup.Compactor
  alias TrpgMaster.Rules.DC, as: DCLoader
  alias TrpgMaster.Rules.Loader, as: RulesLoader

  def lookup_spell(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:spell, name)
  end

  def lookup_class(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:class, name)
  end

  def lookup_item(input) do
    name = Map.get(input, "name", "")
    lookup_compacted(:item, name)
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
      {:ok, entry} when is_map(entry) -> {:ok, Compactor.compact(type, entry)}
      other -> other
    end
  end
end
