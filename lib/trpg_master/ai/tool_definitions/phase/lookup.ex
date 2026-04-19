defmodule TrpgMaster.AI.ToolDefinitions.Phase.Lookup do
  @moduledoc false

  def lookup_spell do
    %{
      name: "lookup_spell",
      description:
        "D&D 5.5e 주문 데이터를 조회한다. 주문 시전, 효과 확인, 규칙 판단 시 사용. 한국어 또는 영어 주문 이름으로 검색 가능. 정확한 이름이 아니어도 부분 검색을 시도한다.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description: "주문 이름 (한국어 또는 영어). 예: \"파이어볼\", \"Fireball\""
          }
        },
        required: ["name"]
      }
    }
  end

  def lookup_monster do
    %{
      name: "lookup_monster",
      description:
        "D&D 5.5e 몬스터/적 데이터를 조회한다. 이름에 해당 단어가 포함된 모든 몬스터를 리스트로 반환한다. " <>
          "예: \"red dragon\" → wyrmling/young/adult/ancient red dragon 전부 반환. " <>
          "한국어/영어 모두 지원. 전투 시작, 적 스탯 확인, 조우 구성 시 사용.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description:
              "몬스터 이름 (한국어 또는 영어, 부분 검색 가능). 예: \"고블린\", \"Goblin\", \"red dragon\", \"드래곤\""
          }
        },
        required: ["name"]
      }
    }
  end

  def search_monsters do
    %{
      name: "search_monsters",
      description:
        "조건에 맞는 몬스터 목록을 검색한다. 파티 레벨에 맞는 CR 범위와 환경/역할 태그로 필터링한다. " <>
          "전투 조우를 구성하거나 즉흥적으로 몬스터를 배치할 때 사용한다. " <>
          "결과는 이름, CR, 크기, 타입 요약 목록으로 반환되며, 상세 스탯은 lookup_monster로 조회한다.",
      input_schema: %{
        type: "object",
        properties: %{
          cr_min: %{
            type: "number",
            description: "최소 CR (포함). 예: 0, 0.25, 1, 5. 파티 레벨 기준: 레벨 ÷ 4 권장"
          },
          cr_max: %{
            type: "number",
            description: "최대 CR (포함). 예: 1, 5, 10, 20. 파티 레벨 기준: 레벨 × 1.5 권장"
          },
          tags: %{
            type: "array",
            items: %{type: "string"},
            description:
              "환경/역할 태그 필터 (AND 조건). " <>
                "환경: forest, dungeon, mountain, swamp, underdark, arctic, desert, coastal, urban, cave, plains, lair. " <>
                "역할: boss, minion, elite, spellcaster, brute, skirmisher, pack, solitary. " <>
                "예: [\"forest\", \"pack\"] → 숲에 나타나고 무리를 짓는 몬스터"
          },
          type: %{
            type: "string",
            description: "몬스터 타입 필터 (부분 일치). 예: \"Dragon\", \"Undead\", \"Beast\", \"Humanoid\""
          },
          limit: %{
            type: "integer",
            description: "반환할 최대 결과 수 (기본 10, 최대 30)"
          }
        },
        required: []
      }
    }
  end

  def lookup_class do
    %{
      name: "lookup_class",
      description: "D&D 5.5e 클래스 정보를 조회한다. 클래스 특성, 레벨업 정보, 주문 목록 등 확인 시 사용.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description: "클래스 이름. 예: \"위자드\", \"Wizard\", \"파이터\""
          }
        },
        required: ["name"]
      }
    }
  end

  def lookup_item do
    %{
      name: "lookup_item",
      description: "D&D 5.5e 아이템/장비 데이터를 조회한다. 무기, 방어구, 마법 아이템, 도구 등의 정보를 확인할 때 사용.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description: "아이템 이름 (한국어 또는 영어). 예: \"대검\", \"Greatsword\""
          }
        },
        required: ["name"]
      }
    }
  end

  def lookup_dc do
    %{
      name: "lookup_dc",
      description: "능력치 판정이나 기술 체크의 난이도 등급(DC)을 결정할 때 참고합니다. DC 테이블과 가이드라인을 반환합니다.",
      input_schema: %{
        type: "object",
        properties: %{
          skill_or_attribute: %{
            type: "string",
            description: "기술명 또는 능력치. 예: \"은신\", \"Stealth\", \"DEX\", \"민첩\""
          },
          context: %{
            type: "string",
            description: "판정 상황 설명 (선택)"
          }
        },
        required: ["skill_or_attribute"]
      }
    }
  end

  def lookup_rule do
    %{
      name: "lookup_rule",
      description:
        "D&D 5.5e 규칙을 조회한다. 전투 규칙, 상태이상 효과, 행동 종류, 피해 유형/저항/면역, 기술 판정, 주문 시전 규칙 등을 확인할 때 사용. 예: \"기절\", \"집중\", \"기회 공격\", \"엄폐\", \"넘어짐\"",
      input_schema: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description:
              "조회할 규칙 키워드. 예: \"기절(Stunned)\", \"집중(Concentration)\", \"공격 행동\", \"독 저항\""
          },
          category: %{
            type: "string",
            description:
              "규칙 카테고리 (선택). 예: \"conditions\", \"combat\", \"actions\", \"damage-and-healing\", \"spellcasting\""
          }
        },
        required: ["query"]
      }
    }
  end
end
