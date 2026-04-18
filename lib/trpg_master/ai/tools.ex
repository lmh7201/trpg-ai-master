defmodule TrpgMaster.AI.Tools do
  @moduledoc """
  Claude에게 제공할 tool 정의 및 실행.
  Phase 1: roll_dice
  Phase 2: lookup_spell, lookup_monster, lookup_class, lookup_item
  """

  alias TrpgMaster.AI.ToolDefinitions
  alias TrpgMaster.Dice.Roller
  alias TrpgMaster.Rules.Loader, as: RulesLoader
  alias TrpgMaster.Rules.DC, as: DCLoader
  alias TrpgMaster.Oracle.Loader, as: OracleLoader

  @doc """
  사용 가능한 tool 목록을 반환한다. phase에 따라 필요한 도구만 포함한다.
  """
  def definitions(phase \\ :exploration), do: ToolDefinitions.definitions(phase)

  @doc """
  상태 변경 도구 정의를 반환한다.
  """
  defdelegate state_tool_definitions(), to: ToolDefinitions

  # ── Tool execution ──────────────────────────────────────────────────────────

  @doc """
  tool_use 요청을 실행하고 결과를 반환한다.
  """
  # 배치 모드: rolls 배열이 있으면 여러 주사위를 한 번에 굴림
  def execute("roll_dice", %{"rolls" => rolls}) when is_list(rolls) and length(rolls) > 0 do
    results =
      Enum.map(rolls, fn roll_input ->
        notation = Map.get(roll_input, "notation", "1d20")

        opts = [
          label: Map.get(roll_input, "label"),
          advantage: Map.get(roll_input, "advantage", false),
          disadvantage: Map.get(roll_input, "disadvantage", false)
        ]

        case Roller.roll(notation, opts) do
          {:ok, result} -> format_tool_result(result)
          {:error, reason} -> %{"error" => reason, "notation" => notation}
        end
      end)

    {:ok, %{"batch" => true, "count" => length(results), "results" => results}}
  end

  # 단일 모드: 기존 동작 유지
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
    lookup_monsters_list(name)
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
          "name" => get_in(m, ["name", "ko"]) || get_in(m, ["name", "en"]),
          "nameEn" => get_in(m, ["name", "en"]),
          "cr" => Map.get(m, "cr"),
          "size" => get_in(m, ["size", "ko"]) || get_in(m, ["size", "en"]),
          "type" => get_in(m, ["type", "ko"]) || get_in(m, ["type", "en"]),
          "tags" => Map.get(m, "tags", [])
        }
      end)

    {:ok,
     %{
       "count" => length(results),
       "monsters" => results,
       "tip" => "상세 스탯은 lookup_monster(name)으로 조회하세요."
     }}
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
    {:ok, %{"status" => "ok", "message" => "현재 위치가 '#{input["location_name"]}'(으)로 변경되었습니다."}}
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
    {:ok, %{"status" => "ok", "message" => "전투가 종료되었습니다. XP가 지급되었으며 레벨업 조건이 충족되면 자동으로 처리됩니다."}}
  end

  def execute("level_up", input) do
    asi_msg =
      case input["asi"] do
        nil ->
          ""

        asi when is_map(asi) ->
          parts = Enum.map(asi, fn {stat, amt} -> "#{stat} +#{amt}" end)
          " ASI 적용: #{Enum.join(parts, ", ")}."
      end

    feat_msg =
      case input["feat"] do
        nil -> ""
        "" -> ""
        feat_name when is_binary(feat_name) -> " 특기 습득: #{feat_name}."
      end

    spells_msg =
      case input["new_spells"] do
        nil ->
          ""

        [] ->
          ""

        spells when is_list(spells) ->
          names = Enum.map(spells, fn s -> s["name"] || "알 수 없음" end)
          " 새 주문 습득: #{Enum.join(names, ", ")}."
      end

    # 새로 얻는 클래스/서브클래스 피처 조회 (AI 서술에 활용)
    characters = Process.get(:campaign_characters, [])

    {features_msg, subclass_features_msg} =
      case Enum.find(characters, fn c ->
             (c["name"] || "") |> String.downcase() ==
               (input["character_name"] || "") |> String.downcase()
           end) do
        nil ->
          {"", ""}

        char ->
          class_id = char["class_id"]
          current_level = char["level"] || 1
          new_level = current_level + 1

          new_features =
            TrpgMaster.Rules.CharacterData.class_features_for_level(class_id, new_level)

          class_feat_msg =
            if new_features != [] do
              " 새 클래스 피처: #{Enum.join(new_features, ", ")}."
            else
              ""
            end

          sub_feat_msg =
            case char["subclass_id"] do
              nil ->
                ""

              subclass_id ->
                new_sub_features =
                  TrpgMaster.Rules.CharacterData.subclass_features_for_level(
                    subclass_id,
                    new_level
                  )

                if new_sub_features != [] do
                  " 새 서브클래스 피처 (#{char["subclass"]}): #{Enum.join(new_sub_features, ", ")}."
                else
                  ""
                end
            end

          {class_feat_msg, sub_feat_msg}
      end

    {:ok,
     %{
       "status" => "ok",
       "message" =>
         "#{input["character_name"]} 레벨업이 처리되었습니다. HP, 숙련 보너스, 주문 슬롯, 클래스/서브클래스 피처가 자동으로 재계산됩니다.#{features_msg}#{subclass_features_msg}#{asi_msg}#{feat_msg}#{spells_msg}",
       "note" => "레벨업 서술 시 위의 새 클래스 피처와 서브클래스 피처를 플레이어에게 설명하세요."
     }}
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
    result =
      case RulesLoader.lookup(type, name) do
        {:ok, entry} ->
          {:ok, entry}

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

  # 몬스터 부분 검색: 이름에 query가 포함된 모든 몬스터를 리스트로 반환
  defp lookup_monsters_list(name) do
    case RulesLoader.lookup(:monster, name) do
      {:ok, entry} ->
        # 정확히 일치하는 경우도 리스트로 반환
        {:ok, %{"count" => 1, "monsters" => [compact_entry(:monster, entry)]}}

      :not_found ->
        case RulesLoader.search(:monster, name) do
          [] ->
            {:ok, %{"error" => "데이터에서 찾을 수 없습니다", "query" => name}}

          entries ->
            compacted = Enum.map(entries, &compact_entry(:monster, &1))
            {:ok, %{"count" => length(compacted), "monsters" => compacted}}
        end
    end
  end

  # 클래스 데이터는 특히 거대하므로 핵심 필드만 반환
  defp compact_entry(:class, entry) do
    Map.take(entry, [
      "id",
      "name",
      "description",
      "primaryAbility",
      "hitPointDie",
      "savingThrowProficiencies",
      "skillProficiencies",
      "weaponProficiencies",
      "armorTraining",
      "startingEquipment",
      "becomingThisClass",
      "classTableGroups",
      "levelFeatures"
    ])
    |> flatten_ko()
  end

  # 몬스터 데이터는 전투에 필요한 필드 위주로 반환
  defp compact_entry(:monster, entry) do
    Map.take(entry, [
      "id",
      "name",
      "size",
      "type",
      "ac",
      "hp",
      "speed",
      "abilities",
      "cr",
      "xp",
      "traits",
      "actions",
      "bonusActions",
      "reactions",
      "legendaryActions",
      "legendaryActionsDesc",
      "immunities",
      "resistances",
      "conditionImmunities",
      "senses",
      "languages",
      "skillProficiencies"
    ])
    |> flatten_ko()
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
                    Map.put(
                      item,
                      "content",
                      Enum.take(sub_content, 3) ++ [%{"type" => "text", "text" => "...(이하 생략)"}]
                    )

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
    |> flatten_ko()
  end

  # 주문 데이터: 불필요 필드 제거 + 소마법 표시
  defp compact_entry(:spell, entry) when is_map(entry) do
    result =
      entry
      |> Map.drop(["source"])
      |> maybe_drop_empty("castingTimeDetails")
      |> maybe_drop_false("isRitual")
      |> maybe_drop_false("concentration")

    result =
      case result["level"] do
        0 -> Map.put(result, "note", "이 주문은 소마법(cantrip)입니다. 주문 슬롯을 소모하지 않습니다.")
        _ -> result
      end

    flatten_ko(result)
  end

  # 아이템 데이터: source 제거
  defp compact_entry(:item, entry) do
    entry
    |> Map.drop(["source"])
    |> flatten_ko()
  end

  # 기타 타입도 한국어 flatten 적용
  defp compact_entry(_type, entry), do: flatten_ko(entry)

  defp maybe_drop_empty(map, key) do
    case Map.get(map, key) do
      %{"ko" => "", "en" => ""} -> Map.delete(map, key)
      "" -> Map.delete(map, key)
      nil -> Map.delete(map, key)
      _ -> map
    end
  end

  defp maybe_drop_false(map, key) do
    if Map.get(map, key) == false, do: Map.delete(map, key), else: map
  end

  # ── 이중 언어 필드 flatten ────────────────────────────────────────────────

  # {"ko": "화염구", "en": "Fireball"} → "화염구" (ko 우선, en 폴백)
  # 맵/리스트를 재귀적으로 순회하여 모든 {ko, en} 객체를 flatten한다.
  defp flatten_ko(%{"ko" => ko, "en" => _} = map) when map_size(map) == 2, do: ko
  defp flatten_ko(%{"ko" => ko} = map) when map_size(map) == 1, do: ko
  defp flatten_ko(%{"en" => en} = map) when map_size(map) == 1, do: en

  defp flatten_ko(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, flatten_ko(v)} end)
  end

  defp flatten_ko(list) when is_list(list) do
    Enum.map(list, &flatten_ko/1)
  end

  defp flatten_ko(other), do: other

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
      nil ->
        false

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
    type_val = Map.get(monster, "type")

    monster_type =
      cond do
        is_map(type_val) -> (type_val["en"] || "") |> String.downcase()
        is_binary(type_val) -> String.downcase(type_val)
        true -> ""
      end

    String.contains?(monster_type, String.downcase(type_filter))
  end
end
