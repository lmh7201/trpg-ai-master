defmodule TrpgMasterWeb.GameComponents do
  @moduledoc """
  캠페인 헤더, 상태바, 캐릭터 시트를 담당하는 UI 컴포넌트 모음.
  공개 컴포넌트 API는 유지하고 구현은 역할별 모듈로 위임한다.
  """

  alias TrpgMasterWeb.Game.{
    CharacterSheetComponents,
    HeaderComponents,
    StatusComponents
  }

  defdelegate campaign_header(assigns), to: HeaderComponents
  defdelegate model_selector_modal(assigns), to: HeaderComponents

  defdelegate campaign_status_bars(assigns), to: StatusComponents
  defdelegate status_bar(assigns), to: StatusComponents

  defdelegate character_sheet_modal(assigns), to: CharacterSheetComponents
end
