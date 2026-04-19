defmodule TrpgMaster.AI.ToolDefinitions.State.Character do
  @moduledoc false

  def get_info do
    %{
      name: "get_character_info",
      description:
        "플레이어 캐릭터의 상세 정보를 조회합니다. 전투, 판정, 주문 사용, 능력치 확인 등 캐릭터 데이터가 필요할 때 반드시 이 도구를 사용하세요. " <>
          "카테고리별로 필요한 정보만 조회하면 효율적입니다.",
      input_schema: %{
        type: "object",
        properties: %{
          category: %{
            type: "string",
            enum: [
              "full",
              "abilities",
              "combat",
              "spells",
              "equipment",
              "features",
              "proficiencies",
              "summary"
            ],
            description:
              "조회할 카테고리. " <>
                "full: 전체 캐릭터 시트, " <>
                "abilities: 능력치/수정치/기술 숙련, " <>
                "combat: HP/AC/속도/무기 숙련/상태이상, " <>
                "spells: 알려진 주문/주문 슬롯, " <>
                "equipment: 장비/인벤토리, " <>
                "features: 클래스/종족 특성, " <>
                "proficiencies: 모든 숙련 정보, " <>
                "summary: 이름/클래스/종족/레벨/HP/AC 요약"
          }
        },
        required: ["category"]
      }
    }
  end

  def update do
    %{
      name: "update_character",
      description: "캐릭터의 상태를 변경한다. HP 변화, 인벤토리 추가/제거, 주문 슬롯 소모, 상태이상 등. 반드시 변경된 필드만 포함한다.",
      input_schema: %{
        type: "object",
        properties: %{
          character_name: %{
            type: "string",
            description: "대상 캐릭터 이름"
          },
          changes: %{
            type: "object",
            description:
              "변경할 필드들. 초기 등록 시: {\"class\": \"위자드\", \"race\": \"하프엘프\", \"level\": 3, \"hp_max\": 20, \"hp_current\": 20, \"ac\": 12, \"inventory\": [\"지팡이\", \"마법서\", \"탐험가 배낭\"]}. 이후 변경 시: {\"hp_current\": 8, \"inventory_add\": [\"치유 물약\"], \"inventory_remove\": [\"화살\"], \"conditions_add\": [\"중독\"]}"
          }
        },
        required: ["character_name", "changes"]
      }
    }
  end
end
