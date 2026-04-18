defmodule TrpgMaster.AI.ToolDefinitions.State do
  @moduledoc false

  def state_tool_definitions do
    [
      get_character_info_def(),
      update_character_def(),
      register_npc_def(),
      update_quest_def(),
      set_location_def(),
      start_combat_def(),
      end_combat_def(),
      write_journal_def(),
      read_journal_def()
    ]
  end

  defp get_character_info_def do
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

  defp update_character_def do
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

  defp register_npc_def do
    %{
      name: "register_npc",
      description: "새로운 NPC를 등록하거나 기존 NPC 정보를 수정한다. NPC가 처음 등장할 때, 또는 NPC의 상태/태도가 변할 때 호출한다.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{type: "string", description: "NPC 이름"},
          description: %{type: "string", description: "NPC 외모/특징 설명"},
          disposition: %{
            type: "string",
            description: "PC에 대한 태도 (우호적/중립/적대적 등)"
          },
          location: %{type: "string", description: "현재 위치"},
          notes: %{type: "string", description: "기타 메모 (비밀, 목표 등)"}
        },
        required: ["name"]
      }
    }
  end

  defp update_quest_def do
    %{
      name: "update_quest",
      description: "퀘스트의 진행 상황을 변경한다. 새 퀘스트 추가, 진행 상태 변경, 완료 처리 등.",
      input_schema: %{
        type: "object",
        properties: %{
          quest_name: %{type: "string", description: "퀘스트 이름"},
          status: %{
            type: "string",
            description: "진행중 | 완료 | 실패 | 발견"
          },
          description: %{type: "string", description: "퀘스트 설명 또는 업데이트 내용"},
          notes: %{type: "string", description: "추가 메모"}
        },
        required: ["quest_name"]
      }
    }
  end

  defp set_location_def do
    %{
      name: "set_location",
      description: "파티의 현재 위치를 변경한다. 새로운 장소에 도착하거나 이동할 때 호출한다.",
      input_schema: %{
        type: "object",
        properties: %{
          location_name: %{type: "string", description: "위치 이름"},
          description: %{type: "string", description: "위치 설명"}
        },
        required: ["location_name"]
      }
    }
  end

  defp start_combat_def do
    %{
      name: "start_combat",
      description:
        "전투를 시작한다. 호출 전에 반드시 모든 적에 대해 lookup_monster로 스탯을 조회해야 한다. 전투 참가자 목록과 함께 호출하고, 이후 각 참가자의 주도권을 roll_dice로 굴린다.",
      input_schema: %{
        type: "object",
        properties: %{
          participants: %{
            type: "array",
            items: %{type: "string"},
            description: "전투 참가자 이름 목록"
          },
          enemies: %{
            type: "array",
            items: %{
              type: "object",
              properties: %{
                name: %{type: "string"},
                hp_max: %{type: "integer"},
                hp_current: %{type: "integer"},
                ac: %{type: "integer"},
                count: %{type: "integer", description: "같은 종류 적 수 (기본 1)"}
              }
            },
            description: "전투에 등장하는 적 목록과 조회된 스탯. lookup_monster 후 이 필드를 채운다."
          }
        },
        required: ["participants"]
      }
    }
  end

  defp end_combat_def do
    %{
      name: "end_combat",
      description: "전투를 종료한다. 전리품과 경험치 정보를 포함할 수 있다.",
      input_schema: %{
        type: "object",
        properties: %{
          loot: %{
            type: "array",
            items: %{type: "string"},
            description: "획득한 전리품 목록"
          },
          xp: %{type: "integer", description: "획득 경험치"},
          summary: %{type: "string", description: "전투 결과 요약"}
        },
        required: []
      }
    }
  end

  defp write_journal_def do
    %{
      name: "write_journal",
      description:
        "DM으로서 중요한 정보를 저널에 기록합니다. 플롯 복선, NPC 비밀, 발견한 단서, 전투 후 메모 등을 기록하세요. 이 정보는 이후 세션에서도 참조됩니다.",
      input_schema: %{
        type: "object",
        properties: %{
          entry: %{
            type: "string",
            description: "저널에 기록할 내용"
          },
          category: %{
            type: "string",
            description: "카테고리: plot | npc | clue | combat | note (기본: note)"
          }
        },
        required: ["entry"]
      }
    }
  end

  defp read_journal_def do
    %{
      name: "read_journal",
      description: "DM 저널에서 이전에 기록한 내용을 읽습니다. 세션 시작 시나 스토리 연속성이 필요할 때 사용하세요.",
      input_schema: %{
        type: "object",
        properties: %{
          category: %{
            type: "string",
            description: "특정 카테고리만 필터링 (plot | npc | clue | combat | note). 생략 시 전체 조회."
          }
        },
        required: []
      }
    }
  end
end
