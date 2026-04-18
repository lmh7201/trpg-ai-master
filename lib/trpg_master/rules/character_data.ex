defmodule TrpgMaster.Rules.CharacterData do
  @moduledoc """
  캐릭터 생성에 필요한 D&D 5.5e 데이터를 로드하고 제공한다.
  DATA_GITHUB_TOKEN이 있으면 GitHub에서 직접 fetch하고,
  없으면 로컬 priv/data/ 파일을 사용한다. ETS에 캐싱한다.
  """

  use GenServer

  alias TrpgMaster.Rules.CharacterData.{Builder, Loader, Progression, Store}

  # ── Public API ──────────────────────────────────────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def classes, do: fetch(:classes, [])
  def races, do: fetch(:races, [])
  def backgrounds, do: fetch(:backgrounds, [])
  def feats, do: fetch(:feats, [])
  def spells, do: fetch(:spells, [])
  def class_features, do: fetch(:class_features, %{})
  def subclasses, do: fetch(:subclasses, [])
  def subclass_features, do: fetch(:subclass_features, %{})
  def weapons, do: fetch(:weapons, [])
  def armor, do: fetch(:armor, [])
  def adventuring_gear, do: fetch(:adventuring_gear, [])
  def tools, do: fetch(:tools, [])
  def monsters, do: fetch(:monsters, [])

  @doc "SRD only 모드 여부 (기본값: true)"
  def srd_only?, do: Application.get_env(:trpg_master, :srd_only, true)

  @doc "SRD 5.2 클래스만 반환"
  def srd_classes, do: Enum.filter(classes(), &(&1["source"] == "SRD 5.2"))

  @doc "SRD 5.2 종족만 반환"
  def srd_races, do: Enum.filter(races(), &(&1["source"] == "SRD 5.2"))

  @doc "SRD 5.2 배경만 반환"
  def srd_backgrounds, do: Enum.filter(backgrounds(), &(&1["source"] == "SRD 5.2"))

  @doc "SRD 5.2 재주만 반환"
  def srd_feats, do: Enum.filter(feats(), &(&1["source"] == "SRD 5.2"))

  @doc """
  특정 클래스 ID와 레벨에서 획득하는 클래스 피처 이름 목록을 반환한다.
  dnd_reference_ko의 classFeatures 데이터를 사용한다 (class_id → [features] 맵 구조).
  반환값: ["피처명1", "피처명2", ...] (해당 레벨에서 새로 얻는 피처만)
  """
  def class_features_for_level(class_id, level),
    do: Progression.class_features_for_level(class_id, level)

  @doc """
  클래스 ID와 레벨 범위에서 획득하는 모든 클래스 피처를 반환한다.
  레벨업 시 old_level+1..new_level 범위의 피처를 한꺼번에 가져올 때 사용한다.
  반환값: [%{"name" => "...", "level" => N}, ...]
  """
  def class_features_for_levels(class_id, from_level, to_level),
    do: Progression.class_features_for_levels(class_id, from_level, to_level)

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
  def level_for_xp(xp), do: Progression.level_for_xp(xp)

  @doc "레벨에 필요한 총 XP를 반환한다"
  def xp_for_level(level), do: Progression.xp_for_level(level)

  @doc "레벨에 따른 숙련 보너스를 반환한다"
  def proficiency_bonus_for_level(level), do: Progression.proficiency_bonus_for_level(level)

  @doc "히트다이스 문자열을 파싱하여 숫자를 반환한다 (예: 'd8' → 8)"
  def parse_hit_die(value), do: Progression.parse_hit_die(value)

  @doc """
  현재 레벨이 ASI(능력치 향상) 레벨인지 확인한다.
  class_id를 전달하면 클래스별 ASI 레벨을 적용한다 (파이터/로그 추가 ASI).
  """
  def asi_level?(level, class_id \\ nil), do: Progression.asi_level?(level, class_id)

  @doc """
  현재 레벨이 서브클래스 선택 레벨인지 확인한다. (5.5e 2024: 모든 클래스 3레벨)
  """
  def subclass_level?(level, class_id \\ nil), do: Progression.subclass_level?(level, class_id)

  @doc """
  클래스 ID에 해당하는 서브클래스 목록을 반환한다.
  서브클래스 데이터 구조: [%{"id" => "...", "classId" => "...", "name" => %{"ko" => "...", "en" => "..."}, ...}]
  """
  def subclasses_for_class(class_id), do: Progression.subclasses_for_class(class_id)

  @doc """
  클래스 ID와 서브클래스 이름(한/영)으로 서브클래스 데이터를 찾아 한국어 이름을 반환한다.
  매칭되지 않으면 입력 이름을 그대로 반환한다.
  """
  def resolve_subclass_name(class_id, subclass_name),
    do: Progression.resolve_subclass_name(class_id, subclass_name)

  @doc """
  클래스 ID와 서브클래스 이름(한/영/id)으로 서브클래스 id를 반환한다.
  매칭되지 않으면 nil을 반환한다.
  """
  def resolve_subclass_id(class_id, subclass_name),
    do: Progression.resolve_subclass_id(class_id, subclass_name)

  @doc """
  특정 서브클래스 ID와 레벨에서 획득하는 서브클래스 피처 이름 목록을 반환한다.
  dnd_reference_ko의 subclassFeatures 데이터를 사용한다 (subclass_id → [features] 맵 구조).
  반환값: ["피처명1", "피처명2", ...] (해당 레벨에서 새로 얻는 피처만)
  """
  def subclass_features_for_level(subclass_id, level),
    do: Progression.subclass_features_for_level(subclass_id, level)

  @doc """
  서브클래스 ID와 레벨 범위에서 획득하는 모든 서브클래스 피처를 반환한다.
  레벨업 시 old_level+1..new_level 범위의 피처를 한꺼번에 가져올 때 사용한다.
  반환값: [%{"name" => "...", "level" => N}, ...]
  """
  def subclass_features_for_levels(subclass_id, from_level, to_level),
    do: Progression.subclass_features_for_levels(subclass_id, from_level, to_level)

  @doc """
  클래스 ID와 레벨에 맞는 주문 슬롯 맵을 반환한다.
  반환 형식: %{"1" => 2, "2" => 3, ...} (슬롯 없으면 nil)
  """
  def spell_slots_for_class_level(class_id, level),
    do: Progression.spell_slots_for_class_level(class_id, level)

  @doc """
  클래스와 레벨에 맞는 소마법(cantrip) 습득 수를 반환한다.
  반환값: 정수 (해당 레벨에서 알 수 있는 소마법 총 수), 해당 클래스 데이터 없으면 nil
  """
  def cantrips_known_for_class_level(class_id, level),
    do: Progression.cantrips_known_for_class_level(class_id, level)

  @doc """
  클래스와 레벨에 맞는 알려진 주문 수(spells known)를 반환한다.
  알려진 주문 방식 캐스터(bard/sorcerer/ranger/warlock)만 정수를 반환한다.
  준비형 캐스터(cleric/druid/wizard 등)는 nil을 반환 — 주문 준비 수 = 레벨 + 능력치 수정치로 계산.
  """
  def spells_known_for_class_level(class_id, level),
    do: Progression.spells_known_for_class_level(class_id, level)

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
  def build_character_map(params), do: Builder.build_character_map(params)

  @doc "캐릭터 정보를 카테고리별로 조회"
  def get_character_info(character, category), do: Builder.get_character_info(character, category)

  @doc false
  def ability_modifier(score), do: Progression.ability_modifier(score)

  # ── GenServer Callbacks ────────────────────────────────────────────────────

  @impl true
  def init(_) do
    Loader.load()
    {:ok, %{}}
  end

  defp fetch(key, default), do: Store.get(key, default)
end
