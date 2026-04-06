defmodule TrpgMaster.Campaign.ToolHandler do
  @moduledoc """
  AI 도구 실행 결과를 캠페인 상태에 반영한다.
  Campaign.Server에서 분리된 순수 상태 변환 모듈.
  """

  alias TrpgMaster.Rules.CharacterData

  require Logger

  @max_journal_entries 100

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  도구 결과 리스트를 순회하며 캠페인 상태에 반영한다.
  """
  def apply_all(state, tool_results) do
    Enum.reduce(tool_results, state, fn result, acc ->
      apply_one(acc, result)
    end)
  end

  # ── 개별 도구 핸들러 ────────────────────────────────────────────────────────

  def apply_one(state, %{tool: "update_character", input: input}) do
    char_name = input["character_name"]
    changes = input["changes"] || %{}

    Logger.info("캐릭터 업데이트: #{char_name} — #{inspect(changes)}")

    characters =
      case find_character_index(state.characters, char_name) do
        nil ->
          # 캐릭터는 반드시 위자드(character_create_live)를 통해서만 생성된다.
          # AI가 update_character로 새 캐릭터를 만드는 것은 허용하지 않는다.
          Logger.warning("update_character: '#{char_name}' 캐릭터 없음 — 무시 (위자드로만 캐릭터 생성 가능)")
          state.characters

        idx ->
          List.update_at(state.characters, idx, fn char ->
            updated = apply_character_changes(char, changes)
            # 레벨이 증가했고 hp_max가 명시되지 않은 경우 자동으로 HP/숙련보너스 재계산
            maybe_apply_level_up_stats(char, updated, changes)
          end)
      end

    state = %{state | characters: characters}

    # 전투 중이면 combat_state["enemies"]의 HP도 동기화
    sync_enemy_hp_to_combat_state(state, char_name, changes)
  end

  def apply_one(state, %{tool: "register_npc", input: input}) do
    name = input["name"]
    Logger.info("NPC 등록: #{name}")

    npc_data =
      Map.merge(
        Map.get(state.npcs, name, %{}),
        input |> Map.drop(["name"]) |> Map.reject(fn {_k, v} -> is_nil(v) end)
      )
      |> Map.put("name", name)

    %{state | npcs: Map.put(state.npcs, name, npc_data)}
  end

  def apply_one(state, %{tool: "update_quest", input: input}) do
    quest_name = input["quest_name"]

    quests =
      case Enum.find_index(state.active_quests, &(&1["name"] == quest_name)) do
        nil ->
          state.active_quests ++
            [
              %{
                "name" => quest_name,
                "status" => input["status"] || "발견",
                "description" => input["description"],
                "notes" => input["notes"]
              }
            ]

        idx ->
          List.update_at(state.active_quests, idx, fn quest ->
            quest
            |> maybe_put("status", input["status"])
            |> maybe_put("description", input["description"])
            |> maybe_put("notes", input["notes"])
          end)
      end

    %{state | active_quests: quests}
  end

  def apply_one(state, %{tool: "set_location", input: input}) do
    Logger.info("위치 변경: #{state.current_location} → #{input["location_name"]}")
    %{state | current_location: input["location_name"]}
  end

  def apply_one(state, %{tool: "start_combat", input: input}) do
    if state.combat_state do
      Logger.warning("[Campaign #{state.id}] 기존 전투가 진행 중인데 새 전투가 시작됨. 기존 전투를 덮어씁니다.")
    end

    participants = input["participants"] || []
    enemies = input["enemies"]
    Logger.info("전투 시작: #{Enum.join(participants, ", ")}")

    player_names = Enum.map(state.characters, fn c -> c["name"] end)

    combat = %{
      "participants" => participants,
      "round" => 1,
      "turn_order" => [],
      "player_names" => player_names
    }

    combat =
      if is_list(enemies) && enemies != [] do
        Map.put(combat, "enemies", enemies)
      else
        combat
      end

    %{state | phase: :combat, combat_state: combat}
  end

  def apply_one(state, %{tool: "end_combat", input: input}) do
    Logger.info("전투 종료")
    player_names = get_in(state.combat_state, ["player_names"]) || []

    characters =
      if player_names != [] do
        Enum.filter(state.characters, fn c -> c["name"] in player_names end)
      else
        state.characters
      end

    xp_gained = input["xp"] || 0

    characters =
      if xp_gained > 0 do
        Enum.map(characters, fn char -> apply_xp_gain(char, xp_gained) end)
      else
        characters
      end

    %{state | phase: :exploration, combat_state: nil, characters: characters}
  end

  def apply_one(state, %{tool: "level_up", input: input}) do
    char_name = input["character_name"]
    asi = input["asi"]
    feat = input["feat"]
    subclass = input["subclass"]
    new_spells = input["new_spells"]
    Logger.info("레벨업 요청: #{char_name}")

    characters =
      case find_character_index(state.characters, char_name) do
        nil ->
          Logger.warning("레벨업 대상 캐릭터 없음: #{char_name}")
          state.characters

        idx ->
          List.update_at(state.characters, idx, fn char ->
            current_level = char["level"] || 1
            current_xp = char["xp"] || 0
            xp_based_level = min(CharacterData.level_for_xp(current_xp), 20)
            # XP 기반 레벨이 더 높으면 그것을 사용, 아니면 1레벨 강제 상승
            target_level = if xp_based_level > current_level, do: xp_based_level, else: current_level + 1
            target_level = min(target_level, 20)

            if target_level > current_level do
              Logger.info("레벨업 적용: #{char_name} #{current_level} → #{target_level}")
              char
              |> apply_level_up(current_level, target_level)
              |> apply_asi(asi)
              |> apply_feat(feat)
              |> apply_subclass(subclass)
              |> apply_new_spells(new_spells)
              # ASI 레벨인데 ASI/feat 선택이 없으면 대기 플래그 설정
              |> then(fn c ->
                if CharacterData.asi_level?(target_level, char["class_id"]) && is_nil(asi) && is_nil(feat) do
                  Map.put(c, "asi_pending", true)
                else
                  Map.delete(c, "asi_pending")
                end
              end)
              # 서브클래스 선택 레벨인데 아직 서브클래스가 없으면 대기 플래그 설정
              |> then(fn c ->
                if CharacterData.subclass_level?(target_level, char["class_id"]) &&
                     is_nil(subclass) && is_nil(c["subclass"]) do
                  Map.put(c, "subclass_pending", true)
                else
                  Map.delete(c, "subclass_pending")
                end
              end)
            else
              Logger.info("레벨업 조건 미충족 또는 최대 레벨: #{char_name} (현재 레벨: #{current_level})")
              char
            end
          end)
      end

    %{state | characters: characters}
  end

  def apply_one(state, %{tool: "write_journal", input: input}) do
    entry_text = input["entry"]
    category = input["category"] || "note"

    entry = %{
      "text" => entry_text,
      "category" => category,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Logger.info("저널 기록 [#{state.id}] [#{category}]: #{String.slice(entry_text, 0, 50)}...")

    entries = (state.journal_entries ++ [entry]) |> Enum.take(-@max_journal_entries)
    %{state | journal_entries: entries}
  end

  def apply_one(state, %{tool: "read_journal", input: _input}) do
    # read_journal은 Tools.execute에서 프로세스 딕셔너리로 처리하므로 상태 변경 없음
    state
  end

  def apply_one(state, result) do
    Logger.debug("알 수 없는 도구 결과 무시: #{inspect(result.tool)}")
    state
  end

  # ── Character Changes ──────────────────────────────────────────────────────

  @doc false
  def apply_character_changes(char, changes) do
    char
    |> maybe_put("hp_current", changes["hp_current"])
    |> maybe_put("hp_max", changes["hp_max"])
    |> maybe_put("class", changes["class"])
    |> maybe_put("level", changes["level"])
    |> maybe_put("xp", changes["xp"])
    |> maybe_put("ac", changes["ac"])
    |> maybe_put("spell_slots", changes["spell_slots"])
    |> merge_spell_slots_used(changes["spell_slots_used"])
    |> maybe_put("race", changes["race"])
    |> maybe_put("inventory", changes["inventory"])
    |> maybe_put("proficiency_bonus", changes["proficiency_bonus"])
    |> maybe_put("abilities", changes["abilities"])
    |> maybe_put("ability_modifiers", changes["ability_modifiers"])
    |> apply_list_change("inventory", changes["inventory_add"], changes["inventory_remove"])
    |> apply_list_change("conditions", changes["conditions_add"], changes["conditions_remove"])
  end

  # ── Level Up ───────────────────────────────────────────────────────────────

  def apply_xp_gain(char, xp_gained) do
    current_xp = char["xp"] || 0
    current_level = char["level"] || 1
    new_xp = current_xp + xp_gained
    new_level = min(CharacterData.level_for_xp(new_xp), 20)

    char = Map.put(char, "xp", new_xp)
    Logger.info("XP 획득: #{char["name"]} #{current_xp} → #{new_xp} XP")

    if new_level > current_level do
      Logger.info("레벨업 발생: #{char["name"]} #{current_level} → #{new_level}")
      leveled = apply_level_up(char, current_level, new_level)
      # ASI 레벨이면 플래그 설정 (AI가 다음 턴에 플레이어에게 선택 요청)
      leveled =
        if CharacterData.asi_level?(new_level, char["class_id"]) do
          Map.put(leveled, "asi_pending", true)
        else
          leveled
        end
      # 서브클래스 선택 레벨이고 아직 서브클래스가 없으면 플래그 설정
      if CharacterData.subclass_level?(new_level, char["class_id"]) &&
           is_nil(char["subclass"]) do
        Map.put(leveled, "subclass_pending", true)
      else
        leveled
      end
    else
      char
    end
  end

  def apply_level_up(char, old_level, new_level) do
    con_mod = get_in(char, ["ability_modifiers", "con"]) || 0
    hit_die = CharacterData.parse_hit_die(char["hit_die"])

    levels_gained = new_level - old_level
    # D&D 5e 평균 규칙: floor(hit_die / 2) + 1 + CON 수정치, 최소 1
    hp_per_level = max(div(hit_die, 2) + 1 + con_mod, 1)
    hp_increase = hp_per_level * levels_gained

    new_hp_max = (char["hp_max"] || 1) + hp_increase
    new_prof_bonus = CharacterData.proficiency_bonus_for_level(new_level)

    # 주문 슬롯 갱신
    class_id = char["class_id"]
    new_spell_slots = CharacterData.spell_slots_for_class_level(class_id, new_level)

    # 소마법/주문 습득 가능 수 갱신 (AI가 new_spells 선택 시 참고)
    new_cantrips_count = CharacterData.cantrips_known_for_class_level(class_id, new_level)
    new_spells_count = CharacterData.spells_known_for_class_level(class_id, new_level)

    # 레벨업으로 새로 획득하는 클래스 피처 누적
    new_class_features = CharacterData.class_features_for_levels(class_id, old_level + 1, new_level)
    existing_class_features = char["class_features"] || []
    merged_class_features = existing_class_features ++ new_class_features

    # 서브클래스 피처 누적
    subclass_id = char["subclass_id"]
    new_subclass_features =
      if subclass_id do
        CharacterData.subclass_features_for_levels(subclass_id, old_level + 1, new_level)
      else
        []
      end

    existing_subclass_features = char["subclass_features"] || []
    merged_subclass_features = existing_subclass_features ++ new_subclass_features

    char
    |> Map.put("level", new_level)
    |> Map.put("hp_max", new_hp_max)
    |> Map.put("hp_current", (char["hp_current"] || 1) + hp_increase)
    |> Map.put("proficiency_bonus", new_prof_bonus)
    |> Map.put("class_features", merged_class_features)
    |> Map.put("subclass_features", merged_subclass_features)
    |> then(fn c ->
      if new_spell_slots do
        c
        |> Map.put("spell_slots", new_spell_slots)
        |> Map.update("spell_slots_used", %{}, fn used ->
          Map.merge(used, Map.new(new_spell_slots, fn {lvl, _} -> {lvl, Map.get(used, lvl, 0)} end))
        end)
      else
        c
      end
    end)
    |> then(fn c ->
      c = if new_cantrips_count, do: Map.put(c, "cantrips_known_count", new_cantrips_count), else: c
      if new_spells_count, do: Map.put(c, "spells_known_count", new_spells_count), else: c
    end)
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp sync_enemy_hp_to_combat_state(%{combat_state: nil} = state, _name, _changes), do: state

  defp sync_enemy_hp_to_combat_state(state, char_name, changes) do
    enemies = get_in(state.combat_state, ["enemies"]) || []
    hp_current = changes["hp_current"]
    normalized = char_name |> String.trim() |> String.downcase()

    match? = fn e -> (e["name"] || "") |> String.trim() |> String.downcase() == normalized end

    if hp_current && Enum.any?(enemies, match?) do
      updated_enemies =
        Enum.map(enemies, fn e ->
          if match?.(e) do
            e
            |> Map.put("hp_current", hp_current)
            |> then(fn e2 ->
              if changes["hp_max"], do: Map.put(e2, "hp_max", changes["hp_max"]), else: e2
            end)
          else
            e
          end
        end)

      put_in(state.combat_state["enemies"], updated_enemies)
    else
      state
    end
  end

  defp find_character_index(characters, name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()
    Enum.find_index(characters, fn c ->
      (c["name"] || "") |> String.trim() |> String.downcase() == normalized
    end)
  end
  defp find_character_index(_characters, _name), do: nil

  defp maybe_apply_level_up_stats(old_char, new_char, changes) do
    old_level = old_char["level"] || 1
    new_level = new_char["level"] || 1

    if new_level > old_level && is_nil(changes["hp_max"]) do
      apply_level_up(new_char, old_level, new_level)
    else
      new_char
    end
  end

  defp apply_asi(char, asi) when is_map(asi) do
    abilities = char["abilities"] || %{}

    new_abilities =
      Enum.reduce(asi, abilities, fn {stat, amount}, acc ->
        current = acc[stat] || 10
        Map.put(acc, stat, min(current + amount, 20))
      end)

    new_modifiers =
      Map.new(new_abilities, fn {k, v} ->
        {k, CharacterData.ability_modifier(v)}
      end)

    char
    |> Map.put("abilities", new_abilities)
    |> Map.put("ability_modifiers", new_modifiers)
  end
  defp apply_asi(char, _), do: char

  defp apply_feat(char, feat_name) when is_binary(feat_name) and feat_name != "" do
    name_lower = String.downcase(feat_name)

    resolved_name =
      CharacterData.feats()
      |> Enum.find(fn f ->
        ko = get_in(f, ["name", "ko"]) || ""
        en = get_in(f, ["name", "en"]) || ""
        String.downcase(ko) == name_lower || String.downcase(en) == name_lower
      end)
      |> case do
        nil -> feat_name
        f -> get_in(f, ["name", "ko"]) || get_in(f, ["name", "en"]) || feat_name
      end

    existing = char["feats"] || []
    if resolved_name in existing do
      char
    else
      Map.put(char, "feats", existing ++ [resolved_name])
    end
  end
  defp apply_feat(char, _), do: char

  defp apply_subclass(char, subclass_name) when is_binary(subclass_name) and subclass_name != "" do
    class_id = char["class_id"]
    resolved = CharacterData.resolve_subclass_name(class_id, subclass_name)
    subclass_id = CharacterData.resolve_subclass_id(class_id, subclass_name)
    Logger.info("서브클래스 선택: #{char["name"]} → #{resolved} (id: #{subclass_id})")

    char = Map.put(char, "subclass", resolved)
    char = if subclass_id, do: Map.put(char, "subclass_id", subclass_id), else: char

    # 선택 레벨의 서브클래스 피처 즉시 부여
    if subclass_id do
      selection_level = char["level"] || 1
      new_features =
        CharacterData.subclass_features_for_level(subclass_id, selection_level)
        |> Enum.map(fn name -> %{"name" => name, "level" => selection_level} end)

      existing = char["subclass_features"] || []
      Map.put(char, "subclass_features", existing ++ new_features)
    else
      char
    end
  end
  defp apply_subclass(char, _), do: char

  defp apply_new_spells(char, nil), do: char
  defp apply_new_spells(char, []), do: char

  defp apply_new_spells(char, new_spells) when is_list(new_spells) do
    Enum.reduce(new_spells, char, fn spell, acc ->
      spell_name = spell["name"] || inspect(spell)

      level_key =
        case spell["level"] do
          0 -> "cantrips"
          n when is_integer(n) and n >= 1 -> Integer.to_string(n)
          _ -> "1"
        end

      Map.update(acc, "spells_known", %{}, fn known ->
        Map.update(known, level_key, [spell_name], fn existing ->
          if spell_name in existing, do: existing, else: existing ++ [spell_name]
        end)
      end)
    end)
  end

  defp apply_new_spells(char, _), do: char

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp apply_list_change(map, key, add, remove) do
    current = Map.get(map, key, [])
    current = if is_list(add), do: current ++ add, else: current
    current = if is_list(remove), do: current -- remove, else: current
    Map.put(map, key, current)
  end

  defp merge_spell_slots_used(char, nil), do: char

  defp merge_spell_slots_used(char, new_used) when is_map(new_used) do
    current = char["spell_slots_used"] || %{}
    merged = Map.merge(current, new_used)
    char = Map.put(char, "spell_slots_used", merged)
    validate_spell_slots_used(char)
  end

  defp validate_spell_slots_used(char) do
    slots = char["spell_slots"] || %{}
    used = char["spell_slots_used"] || %{}

    validated =
      Map.new(used, fn {level, count} ->
        max_slots = slots[level] || 0
        {level, min(count, max_slots)}
      end)

    Map.put(char, "spell_slots_used", validated)
  end
end
