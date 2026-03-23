defmodule TrpgMaster.Rules.CharacterData do
  @moduledoc """
  캐릭터 생성에 필요한 D&D 5.5e 데이터를 로드하고 제공한다.
  DATA_GITHUB_TOKEN이 있으면 GitHub에서 직접 fetch하고,
  없으면 로컬 priv/data/ 파일을 사용한다. ETS에 캐싱한다.
  """

  use GenServer
  require Logger

  @table :character_data

  # D&D 5e XP 임계값 (레벨별 누적 XP, PHB 기준)
  @xp_thresholds [
    {1, 0},       {2, 300},     {3, 900},     {4, 2_700},
    {5, 6_500},   {6, 14_000},  {7, 23_000},  {8, 34_000},
    {9, 48_000},  {10, 64_000}, {11, 85_000}, {12, 100_000},
    {13, 120_000},{14, 140_000},{15, 165_000},{16, 195_000},
    {17, 225_000},{18, 265_000},{19, 305_000},{20, 355_000}
  ]

  # ASI 레벨: 이 레벨 도달 시 능력치 +2 또는 +1/+1 선택 (5.5e 2024 기준)
  # 파이터: 6/14레벨 추가 ASI, 로그: 10레벨 추가 ASI
  @asi_levels %{
    "default" => [4, 8, 12, 16, 19],
    "fighter" => [4, 6, 8, 12, 14, 16, 19],
    "rogue"   => [4, 8, 10, 12, 16, 19]
  }

  # 서브클래스 선택 레벨 (5.5e 2024 기준)
  # 5.5e에서는 모든 클래스가 3레벨에 서브클래스를 선택한다
  @subclass_levels %{
    "default"   => [3],
    "barbarian" => [3],
    "bard"      => [3],
    "cleric"    => [3],
    "druid"     => [3],
    "fighter"   => [3],
    "monk"      => [3],
    "paladin"   => [3],
    "ranger"    => [3],
    "rogue"     => [3],
    "sorcerer"  => [3],
    "warlock"   => [3],
    "wizard"    => [3]
  }

  # SRD 기본 서브클래스 목록 (dnd_reference_ko 데이터 없을 때 폴백)
  @srd_subclasses %{
    "barbarian" => [%{"id" => "berserker",         "name" => %{"ko" => "광전사의 길",    "en" => "Path of the Berserker"}}],
    "bard"      => [%{"id" => "lore",              "name" => %{"ko" => "지식의 학원",    "en" => "College of Lore"}}],
    "cleric"    => [%{"id" => "life",              "name" => %{"ko" => "생명 권능",      "en" => "Life Domain"}}],
    "druid"     => [%{"id" => "moon",              "name" => %{"ko" => "달의 원환",      "en" => "Circle of the Moon"}}],
    "fighter"   => [%{"id" => "champion",          "name" => %{"ko" => "용사",           "en" => "Champion"}}],
    "monk"      => [%{"id" => "open_hand",         "name" => %{"ko" => "열린 손의 전사", "en" => "Warrior of the Open Hand"}}],
    "paladin"   => [%{"id" => "devotion",          "name" => %{"ko" => "헌신의 맹세",   "en" => "Oath of Devotion"}}],
    "ranger"    => [%{"id" => "hunter",            "name" => %{"ko" => "사냥꾼",        "en" => "Hunter"}}],
    "rogue"     => [%{"id" => "thief",             "name" => %{"ko" => "도둑",          "en" => "Thief"}}],
    "sorcerer"  => [%{"id" => "draconic_sorcery",  "name" => %{"ko" => "용혈 마법사",   "en" => "Draconic Sorcery"}}],
    "warlock"   => [%{"id" => "fiend",             "name" => %{"ko" => "악마 계약자",   "en" => "The Fiend"}}],
    "wizard"    => [%{"id" => "abjurer",           "name" => %{"ko" => "방호마법사",    "en" => "Abjurer"}}]
  }

  # D&D 5e 주문 슬롯 테이블 (완전 주문시전자: bard, cleric, druid, sorcerer, wizard)
  # 형식: 레벨 → {1슬롯, 2슬롯, 3슬롯, 4슬롯, 5슬롯, 6슬롯, 7슬롯, 8슬롯, 9슬롯}
  @full_caster_slots %{
    1  => {2, 0, 0, 0, 0, 0, 0, 0, 0},
    2  => {3, 0, 0, 0, 0, 0, 0, 0, 0},
    3  => {4, 2, 0, 0, 0, 0, 0, 0, 0},
    4  => {4, 3, 0, 0, 0, 0, 0, 0, 0},
    5  => {4, 3, 2, 0, 0, 0, 0, 0, 0},
    6  => {4, 3, 3, 0, 0, 0, 0, 0, 0},
    7  => {4, 3, 3, 1, 0, 0, 0, 0, 0},
    8  => {4, 3, 3, 2, 0, 0, 0, 0, 0},
    9  => {4, 3, 3, 3, 1, 0, 0, 0, 0},
    10 => {4, 3, 3, 3, 2, 0, 0, 0, 0},
    11 => {4, 3, 3, 3, 2, 1, 0, 0, 0},
    12 => {4, 3, 3, 3, 2, 1, 0, 0, 0},
    13 => {4, 3, 3, 3, 2, 1, 1, 0, 0},
    14 => {4, 3, 3, 3, 2, 1, 1, 0, 0},
    15 => {4, 3, 3, 3, 2, 1, 1, 1, 0},
    16 => {4, 3, 3, 3, 2, 1, 1, 1, 0},
    17 => {4, 3, 3, 3, 2, 1, 1, 1, 1},
    18 => {4, 3, 3, 3, 3, 1, 1, 1, 1},
    19 => {4, 3, 3, 3, 3, 2, 1, 1, 1},
    20 => {4, 3, 3, 3, 3, 2, 2, 1, 1}
  }

  # 반주문시전자 슬롯 (ranger: 5.5e 2024 기준, 1레벨부터 주문 시작)
  # 형식: 레벨 → {1슬롯, 2슬롯, 3슬롯, 4슬롯, 5슬롯}
  @half_caster_slots %{
    1  => {2, 0, 0, 0, 0},
    2  => {2, 0, 0, 0, 0},
    3  => {3, 0, 0, 0, 0},
    4  => {3, 0, 0, 0, 0},
    5  => {4, 2, 0, 0, 0},
    6  => {4, 2, 0, 0, 0},
    7  => {4, 3, 0, 0, 0},
    8  => {4, 3, 0, 0, 0},
    9  => {4, 3, 2, 0, 0},
    10 => {4, 3, 2, 0, 0},
    11 => {4, 3, 3, 0, 0},
    12 => {4, 3, 3, 0, 0},
    13 => {4, 3, 3, 1, 0},
    14 => {4, 3, 3, 1, 0},
    15 => {4, 3, 3, 2, 0},
    16 => {4, 3, 3, 2, 0},
    17 => {4, 3, 3, 3, 1},
    18 => {4, 3, 3, 3, 1},
    19 => {4, 3, 3, 3, 2},
    20 => {4, 3, 3, 3, 2}
  }

  # 소마법(cantrip) 습득 수 테이블 (5.5e 2024 기준, 클래스별 레벨에 따른 알려진 소마법 수)
  # 형식: 레벨 → 소마법 수
  @cantrips_known %{
    "bard"     => {2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,4},
    "cleric"   => {3,3,3,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,5,5},
    "druid"    => {2,2,2,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,4},
    "sorcerer" => {4,4,4,5,5,5,5,5,5,6,6,6,6,6,6,6,6,6,6,6},
    "warlock"  => {2,3,3,3,3,3,3,3,3,4,4,4,4,4,4,4,4,4,4,4},
    "wizard"   => {3,3,3,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,5,5}
  }

  # 알려진 주문 수 테이블 (5.5e 2024 기준, known-spell 캐스터만)
  # 준비형 캐스터(cleric/druid/wizard/paladin)는 별도 계산이므로 포함하지 않음
  # 형식: 레벨 → 알려진 주문 수
  @spells_known %{
    "bard"     => {4,5,6,7,9,10,11,12,14,15,16,16,17,17,18,18,19,20,22,22},
    "ranger"   => {2,3,4,5,6,6,7,7,9,9,10,10,11,11,12,12,13,13,14,14},
    "sorcerer" => {2,4,6,7,9,10,11,12,14,15,16,16,17,17,18,18,19,20,21,22},
    "warlock"  => {2,3,4,5,6,7,8,9,10,10,11,11,12,12,13,13,14,14,15,15}
  }

  # 워록 계약 마법 슬롯: {슬롯 수, 슬롯 레벨}
  @warlock_pact_slots %{
    1  => {1, 1}, 2  => {2, 1},
    3  => {2, 2}, 4  => {2, 2},
    5  => {2, 3}, 6  => {2, 3},
    7  => {2, 4}, 8  => {2, 4},
    9  => {2, 5}, 10 => {2, 5},
    11 => {3, 5}, 12 => {3, 5},
    13 => {3, 5}, 14 => {3, 5},
    15 => {3, 5}, 16 => {3, 5},
    17 => {4, 5}, 18 => {4, 5},
    19 => {4, 5}, 20 => {4, 5}
  }

  @github_raw_base "https://raw.githubusercontent.com/lmh7201/dnd_reference_ko/main/dnd_korean/dnd-reference/src/data"
  @fetch_timeout 60_000

  @data_mappings [
    {:classes, "classes.json"},
    {:races, "races.json"},
    {:backgrounds, "backgrounds.json"},
    {:feats, "feats.json"},
    {:spells, "spells.json"},
    {:class_features, "classFeatures.json"},
    {:subclasses, "subclasses.json"},
    {:subclass_features, "subclassFeatures.json"},
    {:weapons, "weapons.json"},
    {:armor, "armor.json"},
    {:adventuring_gear, "adventuringGear.json"},
    {:tools, "tools.json"}
  ]

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def classes, do: get(:classes, [])
  def races, do: get(:races, [])
  def backgrounds, do: get(:backgrounds, [])
  def feats, do: get(:feats, [])
  def spells, do: get(:spells, [])
  def class_features, do: get(:class_features, %{})
  def subclasses, do: get(:subclasses, [])
  def subclass_features, do: get(:subclass_features, %{})
  def weapons, do: get(:weapons, [])
  def armor, do: get(:armor, [])
  def adventuring_gear, do: get(:adventuring_gear, [])
  def tools, do: get(:tools, [])

  @doc "클래스 ID로 단일 클래스 조회"
  def get_class(id) do
    Enum.find(classes(), &(&1["id"] == id))
  end

  @doc "종족 ID로 단일 종족 조회"
  def get_race(id) do
    Enum.find(races(), &(&1["id"] == id))
  end

  @doc "배경 ID로 단일 배경 조회"
  def get_background(id) do
    Enum.find(backgrounds(), &(&1["id"] == id))
  end

  @doc "특기 ID로 단일 특기 조회"
  def get_feat(id) do
    Enum.find(feats(), &(&1["id"] == id))
  end

  @doc "출신 특기(origin feat)만 반환"
  def origin_feats do
    Enum.filter(feats(), &(&1["category"] == "origin"))
  end

  @doc "클래스가 사용 가능한 소마법(cantrip) 목록"
  def cantrips_for_class(class_name) do
    spells()
    |> Enum.filter(fn s ->
      s["level"] == 0 &&
        Enum.any?(s["classes"] || [], fn c ->
          String.downcase(c) == String.downcase(class_name)
        end)
    end)
  end

  @doc "클래스가 사용 가능한 1레벨 주문 목록"
  def level1_spells_for_class(class_name) do
    spells()
    |> Enum.filter(fn s ->
      s["level"] == 1 &&
        Enum.any?(s["classes"] || [], fn c ->
          String.downcase(c) == String.downcase(class_name)
        end)
    end)
  end

  @doc "XP로 캐릭터 레벨을 계산한다 (최대 20)"
  def level_for_xp(xp) when is_integer(xp) do
    @xp_thresholds
    |> Enum.filter(fn {_level, required} -> xp >= required end)
    |> List.last()
    |> elem(0)
  end
  def level_for_xp(_), do: 1

  @doc "레벨에 필요한 총 XP를 반환한다"
  def xp_for_level(level) when level in 1..20 do
    {^level, xp} = List.keyfind!(@xp_thresholds, level, 0)
    xp
  end
  def xp_for_level(_), do: 0

  @doc "레벨에 따른 숙련 보너스를 반환한다"
  def proficiency_bonus_for_level(level) when is_integer(level) do
    cond do
      level >= 17 -> 6
      level >= 13 -> 5
      level >= 9  -> 4
      level >= 5  -> 3
      true        -> 2
    end
  end
  def proficiency_bonus_for_level(_), do: 2

  @doc "히트다이스 문자열을 파싱하여 숫자를 반환한다 (예: 'd8' → 8)"
  def parse_hit_die(nil), do: 8
  def parse_hit_die(str) when is_binary(str) do
    case Regex.run(~r/[Dd](\d+)/, str) do
      [_, num] -> String.to_integer(num)
      _ -> 8
    end
  end

  @doc """
  현재 레벨이 ASI(능력치 향상) 레벨인지 확인한다.
  class_id를 전달하면 클래스별 ASI 레벨을 적용한다 (파이터/로그 추가 ASI).
  """
  def asi_level?(level, class_id \\ nil) do
    levels = Map.get(@asi_levels, class_id, @asi_levels["default"])
    level in levels
  end

  @doc """
  현재 레벨이 서브클래스 선택 레벨인지 확인한다. (5.5e 2024: 모든 클래스 3레벨)
  """
  def subclass_level?(level, class_id \\ nil) do
    levels = Map.get(@subclass_levels, class_id, @subclass_levels["default"])
    level in levels
  end

  @doc """
  클래스 ID에 해당하는 서브클래스 목록을 반환한다.
  dnd_reference_ko 데이터를 우선 사용하고, 없으면 SRD 폴백을 반환한다.
  서브클래스 데이터 구조: [%{"id" => "...", "classId" => "...", "name" => %{"ko" => "...", "en" => "..."}, ...}]
  """
  def subclasses_for_class(class_id) when is_binary(class_id) do
    from_data =
      subclasses()
      |> Enum.filter(fn sc ->
        (sc["classId"] || sc["class_id"] || "") == class_id
      end)

    if from_data != [] do
      from_data
    else
      Map.get(@srd_subclasses, class_id, [])
    end
  end
  def subclasses_for_class(_), do: []

  @doc """
  클래스 ID와 서브클래스 이름(한/영)으로 서브클래스 데이터를 찾아 한국어 이름을 반환한다.
  매칭되지 않으면 입력 이름을 그대로 반환한다.
  """
  def resolve_subclass_name(class_id, subclass_name) when is_binary(subclass_name) and subclass_name != "" do
    name_lower = String.downcase(subclass_name)

    subclasses_for_class(class_id)
    |> Enum.find(fn sc ->
      ko = get_in(sc, ["name", "ko"]) || ""
      en = get_in(sc, ["name", "en"]) || sc["name"] || ""
      String.downcase(ko) == name_lower || String.downcase(en) == name_lower
    end)
    |> case do
      nil -> subclass_name
      sc  -> get_in(sc, ["name", "ko"]) || get_in(sc, ["name", "en"]) || subclass_name
    end
  end
  def resolve_subclass_name(_, name), do: name

  @doc """
  클래스 ID와 레벨에 맞는 주문 슬롯 맵을 반환한다.
  반환 형식: %{"1" => 2, "2" => 3, ...} (슬롯 없으면 nil)
  """
  def spell_slots_for_class_level(class_id, level) when is_integer(level) do
    cond do
      class_id in ["bard", "cleric", "druid", "sorcerer", "wizard"] ->
        slots_tuple_to_map(@full_caster_slots[level])

      class_id == "ranger" ->
        slots_tuple_to_map(@half_caster_slots[level])

      class_id == "warlock" ->
        case @warlock_pact_slots[level] do
          {count, slot_level} when count > 0 ->
            %{Integer.to_string(slot_level) => count}
          _ -> nil
        end

      true -> nil
    end
  end
  def spell_slots_for_class_level(_, _), do: nil

  @doc """
  클래스와 레벨에 맞는 소마법(cantrip) 습득 수를 반환한다.
  반환값: 정수 (해당 레벨에서 알 수 있는 소마법 총 수), 해당 클래스 데이터 없으면 nil
  """
  def cantrips_known_for_class_level(class_id, level)
      when is_binary(class_id) and is_integer(level) and level in 1..20 do
    case @cantrips_known[class_id] do
      nil -> nil
      tuple -> elem(tuple, level - 1)
    end
  end
  def cantrips_known_for_class_level(_, _), do: nil

  @doc """
  클래스와 레벨에 맞는 알려진 주문 수(spells known)를 반환한다.
  알려진 주문 방식 캐스터(bard/sorcerer/ranger/warlock)만 정수를 반환한다.
  준비형 캐스터(cleric/druid/wizard 등)는 nil을 반환 — 주문 준비 수 = 레벨 + 능력치 수정치로 계산.
  """
  def spells_known_for_class_level(class_id, level)
      when is_binary(class_id) and is_integer(level) and level in 1..20 do
    case @spells_known[class_id] do
      nil -> nil
      tuple -> elem(tuple, level - 1)
    end
  end
  def spells_known_for_class_level(_, _), do: nil

  @doc "주어진 카테고리의 장비 목록 (weapons, armor, gear, tools)"
  def equipment_by_category(category) do
    case category do
      :weapons -> weapons()
      :armor -> armor()
      :gear -> adventuring_gear()
      :tools -> tools()
      _ -> []
    end
  end

  @doc """
  완성된 캐릭터 데이터를 Campaign.State에 저장할 수 있는 맵으로 변환한다.
  """
  def build_character_map(params) do
    class_data = get_class(params.class_id)
    race_data = get_race(params.race_id)
    background_data = get_background(params.background_id)

    # 한국어 이름 추출
    class_name = class_data["name"] || class_data["nameEn"] || params.class_id
    race_name = extract_race_name(race_data)
    background_name = background_data["name"] || background_data["nameEn"] || params.background_id

    # HP 계산: 1레벨 = hit die 최대값 + CON 수정치
    hit_die = parse_hit_die(class_data["hitPointDie"])
    con_mod = ability_modifier(params.abilities["con"] || 10)
    hp_max = hit_die + con_mod

    # AC 계산
    ac = calculate_ac(params)

    # 기술 숙련 목록 조합 (클래스 선택 + 배경)
    skill_profs = (params[:class_skills] || []) ++ extract_background_skills(background_data)

    # 1레벨 주문 슬롯 초기화
    spell_slots = spell_slots_for_class_level(params.class_id, 1) || %{}

    %{
      "name" => params.name,
      "class" => class_name,
      "class_id" => params.class_id,
      "subclass" => nil,
      "race" => race_name,
      "race_id" => params.race_id,
      "background" => background_name,
      "background_id" => params.background_id,
      "level" => 1,
      "xp" => 0,
      "hp_max" => hp_max,
      "hp_current" => hp_max,
      "hit_die" => class_data["hitPointDie"],
      "ac" => ac,
      "speed" => extract_speed(race_data),
      "proficiency_bonus" => 2,
      "abilities" => params.abilities,
      "ability_modifiers" => calculate_all_modifiers(params.abilities),
      "saving_throws" => class_data["savingThrowProficiencies"],
      "skill_proficiencies" => skill_profs,
      "weapon_proficiencies" => class_data["weaponProficiencies"],
      "armor_training" => class_data["armorTraining"],
      "tool_proficiencies" => extract_tool_prof(background_data),
      "features" => extract_level1_features(class_data, race_data),
      "background_feat" => extract_background_feat(background_data),
      "equipment" => params[:equipment] || [],
      "inventory" => params[:equipment] || [],
      "spells_known" => params[:spells] || %{},
      "conditions" => [],
      "spell_slots" => spell_slots,
      "spell_slots_used" => %{},
      "feats" => []
    }
  end

  @doc "캐릭터 정보를 카테고리별로 조회"
  def get_character_info(character, category) do
    case category do
      "full" ->
        character

      "abilities" ->
        Map.take(character, [
          "abilities", "ability_modifiers", "saving_throws",
          "skill_proficiencies", "proficiency_bonus"
        ])

      "combat" ->
        Map.take(character, [
          "hp_max", "hp_current", "ac", "speed", "hit_die",
          "weapon_proficiencies", "armor_training", "conditions",
          "abilities", "ability_modifiers", "proficiency_bonus"
        ])

      "spells" ->
        Map.take(character, [
          "spells_known", "spell_slots", "spell_slots_used",
          "abilities", "ability_modifiers", "proficiency_bonus", "level", "class_id"
        ])

      "equipment" ->
        Map.take(character, ["equipment", "inventory"])

      "features" ->
        Map.take(character, [
          "features", "background_feat", "class", "race",
          "background", "level"
        ])

      "proficiencies" ->
        Map.take(character, [
          "saving_throws", "skill_proficiencies",
          "weapon_proficiencies", "armor_training",
          "tool_proficiencies", "proficiency_bonus"
        ])

      "summary" ->
        Map.take(character, [
          "name", "class", "race", "background", "level",
          "hp_max", "hp_current", "ac", "speed"
        ])

      _ ->
        %{"error" => "알 수 없는 카테고리: #{category}"}
    end
  end

  # ── GenServer Callbacks ────────────────────────────────────────────────────

  @impl true
  def init(_) do
    :ssl.start()
    :inets.start()

    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])

    token = System.get_env("DATA_GITHUB_TOKEN")

    if is_binary(token) && token != "" do
      load_from_github(token)
    else
      Logger.info("CharacterData: DATA_GITHUB_TOKEN 없음 → 로컬 priv/data/ 파일 사용")
      load_from_local()
    end

    {:ok, %{}}
  end

  # ── Private: Load strategies ─────────────────────────────────────────────

  defp get(key, default) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> default
    end
  end

  defp load_from_github(token) do
    Logger.info("CharacterData: DATA_GITHUB_TOKEN 감지됨 → GitHub에서 데이터 fetch 시작")

    for {key, file} <- @data_mappings do
      url = "#{@github_raw_base}/#{file}"

      case fetch_json(url, token) do
        {:ok, data} ->
          :ets.insert(@table, {key, data})
          Logger.info("CharacterData: [GitHub] #{file} → #{data_count(data)}건")

        {:error, reason} ->
          Logger.warning(
            "CharacterData: [GitHub] #{file} fetch 실패 (#{reason}) → 로컬 파일로 대체"
          )

          load_local_file(key, file)
      end
    end
  end

  defp load_from_local do
    for {key, file} <- @data_mappings do
      load_local_file(key, file)
    end
  end

  defp load_local_file(key, file) do
    path = Application.app_dir(:trpg_master, Path.join("priv/data", file))

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            :ets.insert(@table, {key, data})
            Logger.info("CharacterData: [로컬] #{file} → #{data_count(data)}건")

          {:error, reason} ->
            Logger.warning("CharacterData: JSON 파싱 실패 — #{file}: #{inspect(reason)}")
        end

      {:error, reason} ->
        Logger.warning("CharacterData: 파일 읽기 실패 — #{file}: #{inspect(reason)}")
    end
  end

  # ── GitHub HTTP fetch ──────────────────────────────────────────────────────

  defp fetch_json(url, token) do
    headers = [
      {~c"Authorization", String.to_charlist("token #{token}")},
      {~c"User-Agent", ~c"trpg-ai-master/1.0"}
    ]

    ssl_opts = build_ssl_opts()
    http_opts = [timeout: @fetch_timeout, connect_timeout: 15_000, ssl: ssl_opts]

    case :httpc.request(:get, {String.to_charlist(url), headers}, http_opts, []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(:erlang.list_to_binary(body)) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "JSON 파싱 오류: #{inspect(reason)}"}
        end

      {:ok, {{_, 401, _}, _, _}} ->
        {:error, "인증 실패 (401) — DATA_GITHUB_TOKEN을 확인하세요"}

      {:ok, {{_, 404, _}, _, _}} ->
        {:error, "파일 없음 (404)"}

      {:ok, {{_, status, _}, _, body}} ->
        body_str = :erlang.list_to_binary(body) |> String.slice(0, 200)
        {:error, "HTTP #{status}: #{body_str}"}

      {:error, reason} ->
        {:error, "HTTP 요청 실패: #{inspect(reason)}"}
    end
  end

  defp build_ssl_opts do
    ca_cert_file = System.get_env("SSL_CERT_FILE", "/etc/ssl/certs/ca-certificates.crt")

    if File.exists?(ca_cert_file) do
      [
        verify: :verify_peer,
        cacertfile: String.to_charlist(ca_cert_file),
        depth: 10,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    else
      [verify: :verify_none]
    end
  end

  defp data_count(data) when is_list(data), do: length(data)
  defp data_count(data) when is_map(data), do: map_size(data)
  defp data_count(_), do: 0

  # ── Helper functions ───────────────────────────────────────────────────────

  defp extract_race_name(nil), do: "알 수 없음"
  defp extract_race_name(%{"name" => %{"ko" => ko}}), do: ko
  defp extract_race_name(%{"name" => name}) when is_binary(name), do: name
  defp extract_race_name(_), do: "알 수 없음"

  defp extract_speed(nil), do: 30
  defp extract_speed(%{"basicTraits" => %{"speed" => %{"value" => v}}}), do: v
  defp extract_speed(_), do: 30

  defp extract_background_skills(nil), do: []
  defp extract_background_skills(%{"skillProficiencies" => %{"ko" => skills}}), do: skills
  defp extract_background_skills(%{"skillProficiencies" => %{"en" => skills}}), do: skills
  defp extract_background_skills(_), do: []

  defp extract_tool_prof(nil), do: []
  defp extract_tool_prof(%{"toolProficiency" => %{"ko" => tool}}), do: [tool]
  defp extract_tool_prof(%{"toolProficiency" => %{"en" => tool}}), do: [tool]
  defp extract_tool_prof(_), do: []

  defp extract_background_feat(nil), do: nil
  defp extract_background_feat(%{"feat" => %{"name" => %{"ko" => name}}}), do: name
  defp extract_background_feat(%{"feat" => %{"name" => %{"en" => name}}}), do: name
  defp extract_background_feat(_), do: nil

  defp extract_level1_features(class_data, race_data) do
    class_features =
      case class_data["features"] do
        features when is_list(features) ->
          features
          |> Enum.find(%{}, &(&1["level"] == 1))
          |> Map.get("featuresKo", Map.get(%{}, "features", []))

        _ ->
          []
      end

    race_features =
      case race_data do
        %{"traits" => traits} when is_list(traits) ->
          Enum.map(traits, fn t ->
            get_in(t, ["name", "ko"]) || get_in(t, ["name", "en"]) || "특성"
          end)

        _ ->
          []
      end

    class_features ++ race_features
  end

  def ability_modifier(score) when is_integer(score) do
    div(score - 10, 2)
  end
  def ability_modifier(_), do: 0

  defp calculate_all_modifiers(abilities) when is_map(abilities) do
    Map.new(abilities, fn {key, val} -> {key, ability_modifier(val)} end)
  end
  defp calculate_all_modifiers(_), do: %{}

  # 슬롯 튜플을 %{"1" => n, ...} 맵으로 변환 (0인 슬롯 제외)
  defp slots_tuple_to_map(nil), do: nil
  defp slots_tuple_to_map(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.with_index(1)
    |> Enum.reject(fn {count, _} -> count == 0 end)
    |> Map.new(fn {count, level} -> {Integer.to_string(level), count} end)
    |> case do
      m when map_size(m) == 0 -> nil
      m -> m
    end
  end

  defp calculate_ac(params) do
    # 기본 AC 계산: 장비에 따라 달라짐. 기본값은 10 + DEX mod
    dex_mod = ability_modifier(params.abilities["dex"] || 10)

    case params[:armor_choice] do
      nil -> 10 + dex_mod
      "none" -> 10 + dex_mod
      armor_id ->
        armor_data = Enum.find(flat_armor_list(), &(&1["id"] == armor_id))
        if armor_data, do: compute_armor_ac(armor_data, dex_mod), else: 10 + dex_mod
    end
  end

  defp flat_armor_list do
    data = armor()

    cond do
      is_map(data) -> Map.get(data, "armor", []) ++ Map.get(data, "shields", [])
      is_list(data) -> data
      true -> []
    end
  end

  # AC가 문자열인 경우 파싱: "11 + Dex modifier", "14 + Dex modifier (max 2)", "18" 등
  defp compute_armor_ac(%{"ac" => ac_str}, dex_mod) when is_binary(ac_str) do
    cond do
      # "14 + Dex modifier (max 2)" 같은 패턴
      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier\s*\(max\s*(\d+)\)/i, ac_str) ->
        [_, base_str, max_str] = match
        base = String.to_integer(base_str)
        max_dex = String.to_integer(max_str)
        base + min(dex_mod, max_dex)

      # "11 + Dex modifier" 같은 패턴
      match = Regex.run(~r/^(\d+)\s*\+\s*Dex modifier/i, ac_str) ->
        [_, base_str] = match
        String.to_integer(base_str) + dex_mod

      # 숫자만 있는 경우 "18"
      match = Regex.run(~r/^(\d+)$/, String.trim(ac_str)) ->
        [_, base_str] = match
        String.to_integer(base_str)

      true ->
        10 + dex_mod
    end
  end
  defp compute_armor_ac(%{"ac" => ac_info}, dex_mod) when is_map(ac_info) do
    base = Map.get(ac_info, "base", 10)
    add_dex = Map.get(ac_info, "addDex", true)
    max_dex = Map.get(ac_info, "maxDex")

    cond do
      not add_dex -> base
      max_dex -> base + min(dex_mod, max_dex)
      true -> base + dex_mod
    end
  end
  defp compute_armor_ac(%{"ac" => ac}, _dex_mod) when is_integer(ac), do: ac
  defp compute_armor_ac(_, dex_mod), do: 10 + dex_mod
end
