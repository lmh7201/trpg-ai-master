defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice
  Phase 2: lookup_spell, lookup_monster, lookup_class, lookup_item
  """

  alias TrpgMaster.Dice.Roller
  alias TrpgMaster.Rules.Loader, as: RulesLoader
  alias TrpgMaster.Oracle.Loader, as: OracleLoader

  @doc """
  사용 가능한 tool 목록을 반환한다.
  """
  def definitions do
    [
      roll_dice_def(),
      lookup_spell_def(),
      lookup_monster_def(),
      lookup_class_def(),
      lookup_item_def(),
      consult_oracle_def(),
      list_oracles_def()
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
        "D&D 5e 주문 데이터를 조회한다. 주문 시전, 효과 확인, 규칙 판단 시 사용. 한국어 또는 영어 주문 이름으로 검색 가능. 정확한 이름이 아니어도 부분 검색을 시도한다.",
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
        "D&D 5e 몬스터/적 데이터를 조회한다. 전투 시작, 적 스탯 확인, 조우 구성 시 사용.",
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

  defp lookup_class_def do
    %{
      name: "lookup_class",
      description:
        "D&D 5e 클래스 정보를 조회한다. 클래스 특성, 레벨업 정보, 주문 목록 등 확인 시 사용.",
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
        "D&D 5e 아이템/장비 데이터를 조회한다. 무기, 방어구, 마법 아이템, 도구 등의 정보를 확인할 때 사용.",
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

  # ── State-change tool definitions ────────────────────────────────────────────

  @doc """
  상태 변경 도구 정의를 반환한다.
  """
  def state_tool_definitions do
    [
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
        "전투를 시작한다. 전투 참가자 목록과 함께 호출한다. 이 도구를 호출한 후 각 참가자의 주도권을 roll_dice로 굴린다.",
      input_schema: %{
        type: "object",
        properties: %{
          participants: %{
            type: "array",
            items: %{type: "string"},
            description: "전투 참가자 이름 목록"
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

  def execute(tool_name, _input) do
    {:error, "알 수 없는 도구: #{tool_name}"}
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

  defp lookup_rule(type, name) do
    case RulesLoader.lookup(type, name) do
      {:ok, entry} ->
        {:ok, entry}

      :not_found ->
        case RulesLoader.search(type, name) do
          [first | _] -> {:ok, first}
          [] -> {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}
        end
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

    result_map =
      if result.disadvantage, do: Map.put(result_map, "disadvantage", true), else: result_map

    result_map
  end
end
