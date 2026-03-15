defmodule TrpgMaster.Rules.DC do
  @moduledoc """
  난이도 등급(DC) 데이터를 로드하고 조회하는 모듈.

  앱 시작 시 priv/rules/dc_table.json을 로드하여 Agent에 보관.
  스킬명/능력치로 검색 시 한국어·영어 모두 지원.
  """

  use Agent
  require Logger

  # 스킬명 → 능력치 매핑 (한국어/영어 양쪽 키 지원)
  @skill_to_ability %{
    # STR
    "운동" => "STR", "athletics" => "STR",
    # DEX
    "곡예" => "DEX", "acrobatics" => "DEX",
    "은신" => "DEX", "stealth" => "DEX",
    "손재주" => "DEX", "sleight of hand" => "DEX",
    # INT
    "비전학" => "INT", "arcana" => "INT",
    "역사" => "INT", "history" => "INT",
    "조사" => "INT", "investigation" => "INT",
    "자연" => "INT", "nature" => "INT",
    "종교" => "INT", "religion" => "INT",
    # WIS
    "동물 다루기" => "WIS", "animal handling" => "WIS",
    "통찰" => "WIS", "insight" => "WIS",
    "의술" => "WIS", "medicine" => "WIS",
    "인식" => "WIS", "perception" => "WIS",
    "생존" => "WIS", "survival" => "WIS",
    # CHA
    "속이기" => "CHA", "deception" => "CHA",
    "위협" => "CHA", "intimidation" => "CHA",
    "공연" => "CHA", "performance" => "CHA",
    "설득" => "CHA", "persuasion" => "CHA"
  }

  # 능력치 약어 → 정규화 매핑
  @ability_aliases %{
    "str" => "STR", "근력" => "STR", "힘" => "STR",
    "dex" => "DEX", "민첩" => "DEX",
    "con" => "CON", "건강" => "CON", "체력" => "CON",
    "int" => "INT", "지능" => "INT",
    "wis" => "WIS", "지혜" => "WIS",
    "cha" => "CHA", "매력" => "CHA"
  }

  def start_link(_opts) do
    Agent.start_link(fn -> load_dc_data() end, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  스킬명 또는 능력치로 DC 정보를 조회한다.

  Returns {:ok, result_map} with dc_table, related_ability, related_skills, guidelines.
  """
  def lookup(skill_or_attribute) do
    Agent.get(__MODULE__, fn data ->
      build_result(data, skill_or_attribute)
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────────

  defp load_dc_data do
    path = Application.app_dir(:trpg_master, "priv/rules/dc_table.json")

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} ->
            Logger.info("Rules.DC: dc_table.json 로드 완료")
            data

          {:error, reason} ->
            Logger.warning("Rules.DC: JSON 파싱 실패 — #{inspect(reason)}")
            %{}
        end

      {:error, reason} ->
        Logger.warning("Rules.DC: 파일 읽기 실패 — #{inspect(reason)}")
        %{}
    end
  end

  defp build_result(data, query) do
    normalized = query |> String.trim() |> String.downcase()

    # 능력치 직접 매칭 시도
    ability = resolve_ability(normalized)

    general = Map.get(data, "general", %{})
    skills_data = Map.get(data, "skills", %{})
    guidelines = Map.get(data, "guidelines", "")

    result = %{
      "dc_table" => Map.get(general, "table", []),
      "guidelines" => guidelines
    }

    if ability do
      ability_info = Map.get(skills_data, ability, %{})

      result
      |> Map.put("ability", ability)
      |> Map.put("ability_name", Map.get(ability_info, "name", ability))
      |> Map.put("related_skills", Map.get(ability_info, "skills", []))
    else
      result
      |> Map.put("query", query)
      |> Map.put("note", "정확한 능력치/기술을 특정하지 못했습니다. DC 테이블을 참고하세요.")
    end
  end

  defp resolve_ability(normalized) do
    # 1) 능력치 약어/한국어 직접 매칭
    case Map.get(@ability_aliases, normalized) do
      nil ->
        # 2) 스킬명으로 매칭
        Map.get(@skill_to_ability, normalized)

      ability ->
        ability
    end
  end
end
