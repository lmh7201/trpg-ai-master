defmodule TrpgMaster.AI.ToolDefinitions.State.Combat do
  @moduledoc false

  def start do
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

  def finish do
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
end
