defmodule TrpgMaster.AI.ToolDefinitions.Phase do
  @moduledoc false

  def definitions(:combat) do
    [
      roll_dice_def(),
      lookup_monster_def(),
      lookup_spell_def(),
      lookup_item_def(),
      lookup_rule_def(),
      lookup_dc_def(),
      level_up_def()
    ]
  end

  def definitions(_phase) do
    [
      roll_dice_def(),
      lookup_spell_def(),
      lookup_monster_def(),
      search_monsters_def(),
      lookup_class_def(),
      lookup_item_def(),
      consult_oracle_def(),
      list_oracles_def(),
      lookup_dc_def(),
      lookup_rule_def(),
      level_up_def()
    ]
  end

  defp roll_dice_def do
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

  defp lookup_spell_def do
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

  defp lookup_monster_def do
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

  defp search_monsters_def do
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

  defp lookup_class_def do
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

  defp lookup_item_def do
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

  defp consult_oracle_def do
    %{
      name: "consult_oracle",
      description:
        "오라클 테이블에서 무작위 결과를 뽑아 스토리 방향을 결정한다. AI의 자의적 판단 대신 진정한 무작위성을 제공한다. 예/아니오 판단, NPC 동기, 장소, 분위기, 플롯 반전 결정 시 사용한다.",
      input_schema: %{
        type: "object",
        properties: %{
          oracle_name: %{
            type: "string",
            description:
              "오라클 이름. 사용 가능: \"yes_no\", \"npc_motivation\", \"location\", \"atmosphere\", \"plot_twist\""
          },
          question: %{
            type: "string",
            description: "오라클에 물어보는 질문 또는 결정이 필요한 상황 (선택)"
          }
        },
        required: ["oracle_name"]
      }
    }
  end

  defp list_oracles_def do
    %{
      name: "list_oracles",
      description: "사용 가능한 오라클 목록과 각 오라클의 설명을 반환한다.",
      input_schema: %{
        type: "object",
        properties: %{},
        required: []
      }
    }
  end

  defp lookup_dc_def do
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

  defp lookup_rule_def do
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

  defp level_up_def do
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
