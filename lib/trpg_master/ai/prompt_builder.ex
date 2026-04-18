defmodule TrpgMaster.AI.PromptBuilder do
  @moduledoc """
  시스템 프롬프트 로드 + 캠페인 상태 기반 컨텍스트 조립.
  """

  alias TrpgMaster.AI.PromptBuilder.{Messages, Sections}
  alias TrpgMaster.Campaign.State

  @system_prompt_path "priv/prompts/system_dm.md"

  @doc """
  Campaign.State를 받아서 풍부한 시스템 프롬프트를 조립한다.
  opts로 전투 턴 페이즈를 지정할 수 있다: combat_phase: :player_turn | {:enemy_turn, name, is_last}
  """
  def build(%State{} = state, opts \\ []) do
    base = system_prompt()
    context = Sections.build_campaign_context(state)
    tools_instruction = Sections.state_tools_instruction()
    mode_instruction = Sections.mode_instruction(state.mode)
    summary_section = Sections.build_summary_section(state.context_summary)
    combat_summary_section = Sections.build_combat_summary_section(state.combat_history_summary)
    post_combat_section = Sections.build_post_combat_section(state.post_combat_summary)
    combat_phase_instruction = Sections.build_combat_phase_instruction(opts[:combat_phase])

    "#{base}\n\n#{context}\n\n#{summary_section}#{combat_summary_section}#{post_combat_section}#{combat_phase_instruction}#{tools_instruction}\n\n#{mode_instruction}"
  end

  @doc """
  기본 시스템 프롬프트를 로드한다 (하위 호환).
  """
  def system_prompt do
    case File.read(@system_prompt_path) do
      {:ok, content} -> content
      {:error, _} -> default_system_prompt()
    end
  end

  @doc """
  토큰 예산 기반으로 대화 히스토리를 트리밍한다.
  최근 메시지를 최대한 많이 포함하되 예산 초과 시 오래된 것부터 제거.
  """
  defdelegate build_messages(history), to: Messages

  @doc """
  슬라이딩 윈도우 + 요약 기반 메시지 구성.
  최근 N개 실제 메시지를 보존하고, 그 이전은 요약으로 커버한다.
  """
  def build_messages_with_summary(current_message, context_summary, conversation_history \\ []) do
    Messages.build_messages_with_summary(current_message, context_summary, conversation_history)
  end

  @doc """
  State 기반 턴 메시지 구성.
  """
  def build_turn_messages(state, current_message),
    do: Messages.build_turn_messages(state, current_message, [])

  def build_turn_messages(state, current_message, opts),
    do: Messages.build_turn_messages(state, current_message, opts)

  @doc """
  하위 호환: trim_history/1은 build_messages/1로 대체됨.
  """
  def trim_history(history), do: build_messages(history)

  defp default_system_prompt do
    """
    당신은 D&D 5.5e 솔로 플레이 던전 마스터입니다. 한국어로 진행합니다.

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
