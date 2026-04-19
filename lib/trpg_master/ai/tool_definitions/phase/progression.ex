defmodule TrpgMaster.AI.ToolDefinitions.Phase.Progression do
  @moduledoc false

  def level_up do
    %{
      name: "level_up",
      description:
        "캐릭터를 레벨업시킨다. HP(히트다이스 평균 + CON 수정치), 숙련 보너스, 주문 슬롯, 클래스 피처가 자동으로 재계산된다. " <>
          "end_combat 후 누적 XP가 다음 레벨 임계값을 초과했거나, 마일스톤 레벨업이 적절할 때 호출한다. " <>
          "클래스 피처는 레벨업 시 자동으로 캐릭터 데이터(class_features 필드)에 추가된다. 레벨업 서술 시 새로 얻는 클래스 피처를 플레이어에게 안내한다. " <>
          "ASI 레벨(기본: 4/8/12/16/19, 파이터: +6/14, 로그: +10)에는 플레이어에게 능력치 향상(ASI) 또는 특기(Feat) 중 하나를 선택하도록 안내하고 asi 또는 feat 파라미터로 전달한다. asi와 feat은 동시에 사용할 수 없다. " <>
          "서브클래스 선택 레벨(5.5e 기준: 모든 클래스 3레벨)에 도달하면 플레이어에게 서브클래스를 선택하도록 안내하고 subclass 파라미터로 전달한다. " <>
          "주문시전 클래스(바드/소서러/레인저/워록/위자드/클레릭/드루이드)는 레벨업 시 새 주문을 배울 수 있다. " <>
          "플레이어에게 배울 주문을 선택하도록 안내하고 new_spells 파라미터로 전달한다.",
      input_schema: %{
        type: "object",
        properties: %{
          character_name: %{
            type: "string",
            description: "레벨업할 캐릭터 이름"
          },
          subclass: %{
            type: "string",
            description:
              "서브클래스 선택. 5.5e 기준 모든 클래스가 3레벨에 서브클래스를 선택한다. " <>
                "플레이어가 선택한 서브클래스 이름(한국어 또는 영어)을 전달한다. " <>
                "예: \"용혈 마법사\", \"Draconic Sorcery\", \"생명 권능\", \"Life Domain\", \"용사\", \"Champion\""
          },
          asi: %{
            type: "object",
            description:
              "능력치 향상(ASI) 선택. 기본 ASI 레벨: 4/8/12/16/19 (파이터 추가: 6/14, 로그 추가: 10). " <>
                "+2 배분 예: {\"str\": 2} / +1+1 배분 예: {\"str\": 1, \"dex\": 1}. " <>
                "능력치 키: str, dex, con, int, wis, cha. 각 능력치 상한은 20. feat과 동시 사용 불가.",
            additionalProperties: %{type: "integer"}
          },
          feat: %{
            type: "string",
            description:
              "특기(Feat) 선택. ASI 대신 선택 가능. 특기 이름(한국어 또는 영어)을 전달한다. " <>
                "예: \"경계심\", \"Alert\", \"마법 시전\", \"Magic Initiate\". asi와 동시 사용 불가."
          },
          new_spells: %{
            type: "array",
            description:
              "새로 습득할 주문 목록. 레벨업으로 늘어난 cantrips_known 또는 spells_known 슬롯을 채운다. " <>
                "바드/소서러/레인저/워록은 알려진 주문 수가 고정되므로 반드시 플레이어에게 선택을 요청한다. " <>
                "위자드/클레릭/드루이드도 새 레벨의 주문 슬롯이 생기면 배울 주문을 제안한다.",
            items: %{
              type: "object",
              properties: %{
                name: %{type: "string", description: "주문 이름 (한국어 또는 영어)"},
                level: %{type: "integer", description: "주문 레벨 (소마법=0, 1~9)"}
              },
              required: ["name", "level"]
            }
          }
        },
        required: ["character_name"]
      }
    }
  end
end
