defmodule TrpgMaster.AI.PromptBuilder do
  @moduledoc """
  시스템 프롬프트 로드 + 대화 히스토리 조립.
  Phase 1: 기본 시스템 프롬프트 + 전체 히스토리.
  """

  @system_prompt_path "priv/prompts/system_dm.md"

  @doc """
  시스템 프롬프트를 로드한다.
  """
  def system_prompt do
    case File.read(@system_prompt_path) do
      {:ok, content} -> content
      {:error, _} -> default_system_prompt()
    end
  end

  @doc """
  대화 히스토리를 Claude API 형식으로 변환한다.
  Phase 1에서는 단순히 전체 히스토리를 반환한다.
  """
  def build_messages(conversation_history) do
    conversation_history
  end

  defp default_system_prompt do
    """
    당신은 D&D 5e 솔로 플레이 던전 마스터입니다. 한국어로 진행합니다.

    ## 기본 원칙
    - 모든 서술, 대화, 룰 설명은 한국어로 합니다.
    - 감각적 묘사를 적극 활용합니다.
    - 플레이어 행동에 의미 있는 분기를 제공합니다.

    ## 주사위 규칙
    - 모든 판정은 반드시 roll_dice 도구를 사용합니다.
    - 숫자를 임의로 지어내지 않습니다.

    ## 중요
    - 항상 서술 끝에 행동 유도를 제시합니다.
    - tool use 결과를 자연스러운 서술에 녹여냅니다.
    """
  end
end
