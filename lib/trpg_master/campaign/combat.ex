defmodule TrpgMaster.Campaign.Combat do
  @moduledoc """
  전투 흐름 관리.
  플레이어 턴, 적 그룹별 턴, 라운드 정리, 전투 종료 판단을 담당한다.
  Campaign.Server에서 분리된 모듈.
  """

  alias TrpgMaster.Campaign.Combat.{Runtime, TurnRunner}

  @doc """
  전투 모드에서 플레이어 액션을 처리한다.
  `{:reply, reply_value, new_state}` 튜플을 반환한다.
  """
  def handle_action(message, state, opts \\ []) do
    TurnRunner.handle_action(message, state, opts)
  end

  @doc """
  플레이어 전멸 또는 적 전멸 시 전투 자동 종료 판단.
  """
  def should_end?(state), do: Runtime.should_end?(state)

  @doc """
  전멸 감지 시 강제로 전투를 종료한다.
  """
  def force_end_if_needed(state), do: Runtime.force_end_if_needed(state)

  @doc """
  전투 종료 처리: post_combat_summary 생성, combat_history 초기화.
  """
  def finalize(state, last_response_text), do: Runtime.finalize(state, last_response_text)
end
