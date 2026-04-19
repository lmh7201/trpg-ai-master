defmodule TrpgMaster.AI.ToolDefinitions.Phase.Dice do
  @moduledoc false

  def roll_dice do
    %{
      name: "roll_dice",
      description:
        "주사위를 굴립니다. D&D 표기법을 사용합니다 (예: \"1d20+5\", \"2d6+3\", \"4d8-1\"). " <>
          "모든 판정, 공격, 피해, 능력치 체크에 반드시 이 도구를 사용하세요. " <>
          "여러 주사위를 한 번에 굴리려면 rolls 배열을 사용하세요 (주도권 굴림, 다중 공격 등).",
      input_schema: %{
        type: "object",
        properties: %{
          notation: %{
            type: "string",
            description: "주사위 표기법 — 단일 굴림 (예: \"1d20+5\", \"2d6+3\")"
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
          },
          rolls: %{
            type: "array",
            description:
              "여러 주사위를 한 번에 굴릴 때 사용. notation 대신 이 배열을 사용하세요. " <>
                "예: 주도권 3명 → [{\"notation\": \"1d20+2\", \"label\": \"아리아 주도권\"}, {\"notation\": \"1d20+1\", \"label\": \"고블린 A 주도권\"}, ...]",
            items: %{
              type: "object",
              properties: %{
                notation: %{type: "string", description: "주사위 표기법"},
                label: %{type: "string", description: "굴림 목적"},
                advantage: %{type: "boolean", description: "어드밴티지 여부"},
                disadvantage: %{type: "boolean", description: "디스어드밴티지 여부"}
              },
              required: ["notation"]
            }
          }
        },
        required: []
      }
    }
  end
end
