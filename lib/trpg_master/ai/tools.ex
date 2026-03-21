defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice
  Phase 2: lookup_spell, lookup_monster, lookup_class, lookup_item
  """

  alias TrpgMaster.Dice.Roller
  alias TrpgMaster.Rules.Loader, as: RulesLoader
  alias TrpgMaster.Rules.DC, as: DCLoader
  alias TrpgMaster.Oracle.Loader, as: OracleLoader

  @doc """
  사용 가능한 tool 목록을 반환한다. phase에 따라 필요한 도구만 포함한다.
  """
  def definitions(phase \\ :exploration)

  def definitions(:combat) do
    [
      roll_dice_def(),
      lookup_monster_def(),
      lookup_spell_def(),
      lookup_item_def(),
      lookup_rule_def(),
      combat_round_checklist_def(),
      combat_end_checklist_def(),
      lookup_dc_def()
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
      combat_prep_checklist_def(),
      combat_round_checklist_def(),
      combat_end_checklist_def(),
      lookup_dc_def(),
      lookup_rule_def()
    ]
  end

  # ── Tool definitions ────────────────────────────────────────────────────────

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
        "D&D 5.5e 몬스터/적 데이터를 조회한다. 전투 시작, 적 스탯 확인, 조우 구성 시 사용.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{
            type: "string",
            description: "몬스터 이름 (한국어 또는 영어). 예: \"고블린\", \"Goblin\""
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
      description:
        "D&D 5.5e 클래스 정보를 조회한다. 클래스 특성, 레벨업 정보, 주문 목록 등 확인 시 사용.",
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
      description:
        "D&D 5.5e 아이템/장비 데이터를 조회한다. 무기, 방어구, 마법 아이템, 도구 등의 정보를 확인할 때 사용.",
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

  defp combat_prep_checklist_def do
    %{
      name: "combat_prep_checklist",
      description: "전투를 시작하기 전에 반드시 이 도구를 호출하여 전투 계획을 세웁니다.",
      input_schema: %{
        type: "object",
        properties: %{},
        required: []
      }
    }
  end

  defp combat_round_checklist_def do
    %{
      name: "combat_round_checklist",
      description: "전투의 각 라운드 시작 시 이 도구를 호출하여 확인합니다.",
      input_schema: %{
        type: "object",
        properties: %{},
        required: []
      }
    }
  end

  defp combat_end_checklist_def do
    %{
      name: "combat_end_checklist",
      description: "전투 종료 후 이 도구를 호출하여 마무리합니다.",
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
      description:
        "능력치 판정이나 기술 체크의 난이도 등급(DC)을 결정할 때 참고합니다. DC 테이블과 가이드라인을 반환합니다.",
      input_schema: %{
        type: "object",
        properties: %{
          skill_or_attribute: %{
            type: "string",
            description:
              "기술명 또는 능력치. 예: \"은신\", \"Stealth\", \"DEX\", \"민첩\""
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

  # ── State-change tool definitions ────────────────────────────────────────────

  @doc """
  상태 변경 도구 정의를 반환한다.
  """
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
            enum: ["full", "abilities", "combat", "spells", "equipment", "features", "proficiencies", "summary"],
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
      description:
        "캐릭터의 상태를 변경한다. HP 변화, 인벤토리 추가/제거, 주문 슬롯 소모, 상태이상 등. 반드시 변경된 필드만 포함한다.",
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
      description:
        "새로운 NPC를 등록하거나 기존 NPC 정보를 수정한다. NPC가 처음 등장할 때, 또는 NPC의 상태/태도가 변할 때 호출한다.",
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
      description:
        "퀘스트의 진행 상황을 변경한다. 새 퀘스트 추가, 진행 상태 변경, 완료 처리 등.",
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
      description:
        "파티의 현재 위치를 변경한다. 새로운 장소에 도착하거나 이동할 때 호출한다.",
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
            description:
              "전투에 등장하는 적 목록과 조회된 스탯. lookup_monster 후 이 필드를 채운다."
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
      description:
        "DM 저널에서 이전에 기록한 내용을 읽습니다. 세션 시작 시나 스토리 연속성이 필요할 때 사용하세요.",
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

  # ── Tool execution ──────────────────────────────────────────────────────────

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

  def execute("lookup_spell", input) do
    name = Map.get(input, "name", "")
    lookup_rule(:spell, name)
  end

  def execute("lookup_monster", input) do
    name = Map.get(input, "name", "")
    lookup_rule(:monster, name)
  end

  def execute("search_monsters", input) do
    cr_min = Map.get(input, "cr_min")
    cr_max = Map.get(input, "cr_max")
    tags = Map.get(input, "tags", [])
    type_filter = Map.get(input, "type")
    limit = min(Map.get(input, "limit", 10), 30)

    all_monsters = RulesLoader.list(:monster)

    results =
      all_monsters
      |> Enum.filter(fn m -> matches_cr(m, cr_min, cr_max) end)
      |> Enum.filter(fn m -> matches_tags(m, tags) end)
      |> Enum.filter(fn m -> matches_type(m, type_filter) end)
      |> Enum.take(limit)
      |> Enum.map(fn m ->
        %{
          "name" => Map.get(m, "name"),
          "nameEn" => Map.get(m, "nameEn"),
          "cr" => Map.get(m, "cr"),
          "size" => Map.get(m, "sizeKo") || Map.get(m, "size"),
          "type" => Map.get(m, "typeKo") || Map.get(m, "type"),
          "tags" => Map.get(m, "tags", [])
        }
      end)

    {:ok, %{"count" => length(results), "monsters" => results,
            "tip" => "상세 스탯은 lookup_monster(name)으로 조회하세요."}}
  end

  def execute("lookup_class", input) do
    name = Map.get(input, "name", "")
    lookup_rule(:class, name)
  end

  def execute("lookup_item", input) do
    name = Map.get(input, "name", "")
    lookup_rule(:item, name)
  end

  def execute("consult_oracle", input) do
    oracle_name = Map.get(input, "oracle_name", "")
    question = Map.get(input, "question")

    case OracleLoader.random_result(oracle_name) do
      {:ok, result} ->
        response = %{"oracle" => oracle_name, "result" => result}
        response = if question, do: Map.put(response, "question", question), else: response
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("list_oracles", _input) do
    oracles =
      OracleLoader.list()
      |> Enum.map(fn oracle ->
        meta = oracle["metadata"] || %{}

        %{
          "name" => meta["name"],
          "name_ko" => meta["name_ko"],
          "description" => meta["description"],
          "category" => meta["category"]
        }
      end)
      |> Enum.sort_by(& &1["name"])

    {:ok, %{"oracles" => oracles}}
  end

  def execute("lookup_rule", input) do
    query = Map.get(input, "query", "")
    category = Map.get(input, "category")

    # category가 주어지면 해당 카테고리 문서를 먼저 시도
    if category do
      case RulesLoader.lookup(:rule, category) do
        {:ok, entry} -> {:ok, entry}
        :not_found -> lookup_rule(:rule, query)
      end
    else
      lookup_rule(:rule, query)
    end
  end

  def execute("lookup_dc", input) do
    skill_or_attribute = Map.get(input, "skill_or_attribute", "")
    result = DCLoader.lookup(skill_or_attribute)
    context = Map.get(input, "context")
    result = if context, do: Map.put(result, "context", context), else: result
    {:ok, result}
  end

  # Character info lookup: reads from process dictionary (set by Campaign.Server before AI call)
  def execute("get_character_info", input) do
    category = Map.get(input, "category", "summary")
    characters = Process.get(:campaign_characters, [])

    case characters do
      [character | _] ->
        info = TrpgMaster.Rules.CharacterData.get_character_info(character, category)
        {:ok, %{"status" => "ok", "character" => info}}

      [] ->
        {:ok, %{"status" => "error", "message" => "등록된 캐릭터가 없습니다."}}
    end
  end

  # State-change tools: return confirmation, actual state update happens in Campaign.Server
  def execute("update_character", input) do
    {:ok, %{"status" => "ok", "message" => "#{input["character_name"]}의 상태가 업데이트되었습니다."}}
  end

  def execute("register_npc", input) do
    {:ok, %{"status" => "ok", "message" => "NPC '#{input["name"]}'이(가) 등록/수정되었습니다."}}
  end

  def execute("update_quest", input) do
    {:ok,
     %{
       "status" => "ok",
       "message" => "퀘스트 '#{input["quest_name"]}'이(가) 업데이트되었습니다."
     }}
  end

  def execute("set_location", input) do
    {:ok,
     %{"status" => "ok", "message" => "현재 위치가 '#{input["location_name"]}'(으)로 변경되었습니다."}}
  end

  def execute("start_combat", input) do
    participants = input["participants"] || []

    {:ok,
     %{
       "status" => "ok",
       "message" => "전투가 시작되었습니다. 참가자: #{Enum.join(participants, ", ")}"
     }}
  end

  def execute("end_combat", _input) do
    {:ok, %{"status" => "ok", "message" => "전투가 종료되었습니다."}}
  end

  # Journal tools: write_journal state update happens in Campaign.Server
  def execute("write_journal", _input) do
    {:ok, %{"status" => "ok", "message" => "저널에 기록되었습니다."}}
  end

  def execute("read_journal", input) do
    # Campaign.Server가 Client.chat 호출 전 프로세스 딕셔너리에 저장해둔 데이터를 읽음
    category = Map.get(input, "category")
    entries = Process.get(:journal_entries, [])

    filtered =
      if category do
        Enum.filter(entries, &(&1["category"] == category))
      else
        entries
      end

    {:ok, %{"status" => "ok", "entries" => filtered, "total" => length(filtered)}}
  end

  def execute("combat_prep_checklist", _input) do
    checklist = """
    전투 준비 체크리스트:
    0. 몬스터 스탯 조회: 등장하는 모든 적에 대해 lookup_monster를 즉시 호출한다.
       조회한 AC, HP(최대치), 공격 수정치, 피해 주사위, 특수 능력을 기억하고 전투에 사용한다.
       HP는 조회된 hp 값을 기준으로 실제 HP를 roll_dice로 굴려 결정한다 (또는 평균값 사용).
    1. 몬스터 목표: 각 적은 이 전투에서 무엇을 원하는가? (생존, 약탈, 영역 방어, 복수, 시간 벌기, 보호)
    2. 행동 패턴: 각 적의 전투 성향을 정한다 (매복, 비열한 전투, 리더 보호, 열세 시 도주)
    3. 환경 활용: 최소 2가지 환경 요소를 파악한다 (엄폐물, 위험 지형, 고도차, 어둠, 좁은 통로)
    4. 퇴각 경로: 몬스터가 도망칠 수 있는 경로를 설정한다
    5. 전리품/단서: 적이 소지하거나 떨어뜨릴 수 있는 아이템/정보를 정한다
    위 항목을 각각 1~2문장으로 계획한 후, start_combat의 enemies 필드에 조회된 스탯을 채워 호출하고, roll_dice로 주도권을 굴리세요.
    """

    {:ok, %{"checklist" => String.trim(checklist)}}
  end

  def execute("combat_round_checklist", _input) do
    checklist = """
    라운드 체크리스트:
    1. 주도권 순서 확인: 이번 라운드의 행동 순서를 확인
    2. 집중 주문: 집중력 유지 중인 주문이 있는지 확인
    3. 상태이상: 진행 중인 상태이상 효과 처리 (독, 기절, 공포 등)
    4. 환경 변화: 전투 중 환경이 변하는 요소가 있는지 확인
    5. 사기 확인: HP가 50% 이하인 적은 도주를 고려
    """

    {:ok, %{"checklist" => String.trim(checklist)}}
  end

  def execute("combat_end_checklist", _input) do
    checklist = """
    전투 종료 체크리스트:
    1. 전리품 배분: 적에게서 획득한 아이템/금화를 정리
    2. 경험치 계산: 전투 보상 경험치 합산
    3. HP/자원 확인: 파티원의 현재 HP와 소모된 자원(주문 슬롯, 아이템) 정리
    4. 도주한 적: 도망친 적이 있다면 기록 (나중에 재등장 가능)
    5. 스토리 영향: 이 전투가 스토리에 미치는 영향을 정리
    확인 후 update_character로 캐릭터 상태를 업데이트하고, write_journal로 전투 결과를 기록하세요.
    """

    {:ok, %{"checklist" => String.trim(checklist)}}
  end

  def execute(tool_name, _input) do
    {:error, "알 수 없는 도구: #{tool_name}"}
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp lookup_rule(type, name) do
    result =
      case RulesLoader.lookup(type, name) do
        {:ok, entry} -> {:ok, entry}
        :not_found ->
          case RulesLoader.search(type, name) do
            [first | _] -> {:ok, first}
            [] -> {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}
          end
      end

    case result do
      {:ok, entry} when is_map(entry) -> {:ok, compact_entry(type, entry)}
      other -> other
    end
  end

  # 클래스 데이터는 특히 거대하므로 핵심 필드만 반환
  defp compact_entry(:class, entry) do
    Map.take(entry, [
      "name", "nameEn", "description", "descriptionEn",
      "primaryAbility", "hitPointDie", "savingThrowProficiencies",
      "skillProficiencies", "weaponProficiencies", "armorTraining",
      "startingEquipment", "becomingThisClass",
      "classTableGroups", "levelFeatures"
    ])
  end

  # 몬스터 데이터는 전투에 필요한 필드 위주로 반환
  defp compact_entry(:monster, entry) do
    Map.take(entry, [
      "name", "nameEn", "size", "sizeKo", "type", "typeKo",
      "ac", "acKo", "hp", "hpKo", "speed", "speedKo",
      "abilities", "cr", "crKo", "xp",
      "traits", "actions", "bonusActions", "reactions",
      "legendaryActions", "legendaryActionsDesc", "legendaryActionsDescKo",
      "immunities", "immunitiesKo", "resistances", "resistancesKo",
      "conditionImmunities", "conditionImmunitiesKo",
      "senses", "sensesKo", "languages", "languagesKo",
      "skillProficiencies", "skillProficienciesKo"
    ])
  end

  # 룰 문서는 sections 안의 content가 매우 클 수 있으므로 상위 구조만 반환
  defp compact_entry(:rule, %{"sections" => sections} = entry) when is_list(sections) do
    compact_sections =
      Enum.map(sections, fn section ->
        Map.take(section, ["id", "title", "content"])
        |> Map.update("content", [], fn content ->
          if is_list(content) do
            Enum.map(content, fn item ->
              if is_map(item) do
                case Map.get(item, "content") do
                  sub_content when is_list(sub_content) and length(sub_content) > 3 ->
                    Map.put(item, "content", Enum.take(sub_content, 3) ++ [%{"type" => "text", "text" => "...(이하 생략)"}])
                  _ ->
                    item
                end
              else
                item
              end
            end)
          else
            content
          end
        end)
      end)

    Map.put(entry, "sections", compact_sections)
  end

  # 기타 타입은 그대로 반환
  defp compact_entry(_type, entry), do: entry

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

  defp matches_cr(_monster, nil, nil), do: true

  defp matches_cr(monster, cr_min, cr_max) do
    cr_val = RulesLoader.parse_cr(Map.get(monster, "cr", ""))

    case cr_val do
      nil -> false
      val ->
        above_min = is_nil(cr_min) || val >= cr_min
        below_max = is_nil(cr_max) || val <= cr_max
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
    monster_type = Map.get(monster, "type", "") |> String.downcase()
    String.contains?(monster_type, String.downcase(type_filter))
  end
end
