defmodule TrpgMaster.Characters.Creation do
  @moduledoc """
  캐릭터 생성 위저드의 상태 계산, 검증, 최종 캐릭터 조립을 담당한다.
  """

  alias TrpgMaster.Characters.Creation.{Builder, Spellcasting, State, Validation}

  defdelegate initial_state(classes, races, backgrounds), to: State
  defdelegate class_selection(class), to: State
  defdelegate background_selection(background), to: State
  defdelegate ability_method_updates(method), to: State
  defdelegate assign_ability(assigns, key, value), to: State
  defdelegate clear_ability(assigns, key), to: State
  defdelegate roll_abilities(), to: State

  defdelegate validate_step(assigns), to: Validation

  defdelegate prepare_step(assigns, step), to: Spellcasting
  defdelegate resolved_spell_limit(assigns), to: Spellcasting

  defdelegate build_character(assigns), to: Builder
  defdelegate collect_equipment(assigns), to: Builder
end
