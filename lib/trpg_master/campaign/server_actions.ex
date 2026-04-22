defmodule TrpgMaster.Campaign.ServerActions do
  @moduledoc """
  `Campaign.Server`의 단순 상태 변경 로직을 순수 함수로 분리한 모듈.

  `Server`는 이 모듈을 호출해 새 state를 만들고, 비동기 저장 및 반환만 담당한다.
  이렇게 나누면 상태 변경 규칙만 단위 테스트할 수 있다.
  """

  alias TrpgMaster.Campaign.State

  @type mode :: :adventure | :debug
  @type result :: {new_state :: State.t(), log :: String.t()}

  @doc """
  현재 state를 `character`로 교체한다. 지금은 파티가 1인이므로 리스트를 재설정한다.
  """
  @spec set_character(State.t(), map()) :: result()
  def set_character(%State{} = state, character) when is_map(character) do
    new_state = %{state | characters: [character]}
    log = "캐릭터 등록 [#{state.id}]: #{character["name"]}"
    {new_state, log}
  end

  @doc """
  모드를 변경한다. 허용 모드가 아니면 원본 state와 경고 로그를 돌려준다.
  """
  @spec set_mode(State.t(), mode()) :: result()
  def set_mode(%State{} = state, mode) when mode in [:adventure, :debug] do
    new_state = %{state | mode: mode}
    log = "모드 변경 [#{state.id}]: #{state.mode} → #{mode}"
    {new_state, log}
  end

  @doc """
  AI 모델 ID를 변경한다.
  """
  @spec set_model(State.t(), String.t() | nil) :: result()
  def set_model(%State{} = state, model_id) do
    new_state = %{state | ai_model: model_id}
    log = "AI 모델 변경 [#{state.id}]: #{state.ai_model} → #{model_id}"
    {new_state, log}
  end

  @doc """
  세션 종료 후 히스토리/요약 필드를 비우는 순수 함수.
  """
  @spec clear_session_state(State.t()) :: State.t()
  def clear_session_state(%State{} = state) do
    %{
      state
      | exploration_history: [],
        combat_history: [],
        combat_history_summary: nil,
        post_combat_summary: nil,
        context_summary: nil
    }
  end

  @doc """
  player_action 시작 시 turn_count를 증가시킨다.
  """
  @spec advance_turn(State.t()) :: State.t()
  def advance_turn(%State{} = state) do
    %{state | turn_count: state.turn_count + 1}
  end
end
