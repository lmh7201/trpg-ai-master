defmodule TrpgMaster.AI.ToolExecutor.Dice do
  @moduledoc false

  alias TrpgMaster.Dice.Roller

  def execute(%{"rolls" => rolls}) when is_list(rolls) and length(rolls) > 0 do
    results =
      Enum.map(rolls, fn roll_input ->
        notation = Map.get(roll_input, "notation", "1d20")

        opts = [
          label: Map.get(roll_input, "label"),
          advantage: Map.get(roll_input, "advantage", false),
          disadvantage: Map.get(roll_input, "disadvantage", false)
        ]

        case Roller.roll(notation, opts) do
          {:ok, result} -> format_tool_result(result)
          {:error, reason} -> %{"error" => reason, "notation" => notation}
        end
      end)

    {:ok, %{"batch" => true, "count" => length(results), "results" => results}}
  end

  def execute(input) do
    notation = Map.get(input, "notation", "1d20")

    opts = [
      label: Map.get(input, "label"),
      advantage: Map.get(input, "advantage", false),
      disadvantage: Map.get(input, "disadvantage", false)
    ]

    case Roller.roll(notation, opts) do
      {:ok, result} ->
        {:ok, format_tool_result(result)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_tool_result(result) do
    formatted = Roller.format_result(result)

    result_map = %{
      "notation" => result.notation,
      "rolls" => result.rolls,
      "modifier" => result.modifier,
      "total" => result.total,
      "formatted" => formatted,
      "natural_20" => result.natural_20,
      "natural_1" => result.natural_1
    }

    result_map =
      if result.label, do: Map.put(result_map, "label", result.label), else: result_map

    result_map =
      if result.advantage, do: Map.put(result_map, "advantage", true), else: result_map

    if result.disadvantage, do: Map.put(result_map, "disadvantage", true), else: result_map
  end
end
