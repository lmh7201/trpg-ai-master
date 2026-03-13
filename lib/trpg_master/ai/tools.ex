defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice
  Phase 2: lookup_spell, lookup_monster, lookup_class, lookup_item
  """

  alias TrpgMaster.Dice.Roller
  alias TrpgMaster.Rules.Loader, as: RulesLoader

  @doc """
  사용 가능한 tool 목록을 반환한다.
  """
  def definitions do
    [
      roll_dice_def(),
      lookup_spell_def(),
      lookup_monster_def(),
      lookup_class_def(),
      lookup_item_def()
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
