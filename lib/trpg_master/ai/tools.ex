defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice만 구현.
  """

  alias TrpgMaster.Dice.Roller

  @doc """
  Phase 1에서 사용 가능한 tool 목록을 반환한다.
  """
  def definitions do
    [roll_dice_def()]
  end

  defp roll_dice_def do
    %{
      name: "roll_dice",
      description:
        "주사위를 굴립니다. D&D 표기법을 사용합니다 (예: \"1d20+5\", \"2d6+3\", \"4d8-1\"). 모든 판정, 공격, 피해, 능력치 체크에 반드시 이 도구를 사용하세요.",
      input_schema: %{
        type: "object",
        properties: %{
          notation: %{
            type: "string",
            description: "주사위 표기법 (예: \"1d20+5\", \"2d6+3\")"
          },
          label: %{
            type: "string",
            description: "이 주사위 굴림의 목적 (예: \"공격 굴림\", \"인식 판정\", \"화염구 피해\")"
          },
          advantage: %{
            type: "boolean",
            description: "어드밴티지 여부 (d20을 2번 굴려 높은 값 선택)"
          },
          disadvantage: %{
            type: "boolean",
            description: "디스어드밴티지 여부 (d20을 2번 굴려 낮은 값 선택)"
          }
        },
        required: ["notation"]
      }
    }
  end

  @doc """
  tool_use 요청을 실행하고 결과를 반환한다.
  """
  def execute("roll_dice", input) do
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

  def execute(tool_name, _input) do
    {:error, "알 수 없는 도구: #{tool_name}"}
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

    result_map =
      if result.disadvantage, do: Map.put(result_map, "disadvantage", true), else: result_map

    result_map
  end
end
