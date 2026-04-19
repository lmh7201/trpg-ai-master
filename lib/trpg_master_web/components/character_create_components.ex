defmodule TrpgMasterWeb.CharacterCreateComponents do
  @moduledoc """
  캐릭터 생성 위저드의 단계별 UI를 담당하는 컴포넌트 모음.
  공개 컴포넌트 API는 유지하고 구현은 역할별 모듈로 위임한다.
  """

  alias TrpgMasterWeb.CharacterCreate.{
    ProgressionComponents,
    ShellComponents,
    SelectionComponents,
    SummaryComponents
  }

  defdelegate wizard_shell(assigns), to: ShellComponents

  defdelegate class_step(assigns), to: SelectionComponents
  defdelegate race_step(assigns), to: SelectionComponents
  defdelegate background_step(assigns), to: SelectionComponents

  defdelegate abilities_step(assigns), to: ProgressionComponents
  defdelegate equipment_step(assigns), to: ProgressionComponents
  defdelegate spells_step(assigns), to: ProgressionComponents

  defdelegate summary_step(assigns), to: SummaryComponents
end
