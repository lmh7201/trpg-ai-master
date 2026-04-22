defmodule TrpgMasterWeb.ChatComponents do
  @moduledoc """
  캠페인 채팅 메시지, 피드, 입력 폼을 담당하는 컴포넌트 모음.
  공개 컴포넌트 API는 유지하고 구현은 역할별 모듈로 위임한다.

  - 메시지 종류별 말풍선: `TrpgMasterWeb.Chat.Messages`
  - 메시지 피드/타이핑 인디케이터: `TrpgMasterWeb.Chat.Feed`
  - 채팅 입력 폼: `TrpgMasterWeb.Chat.Input`
  """

  alias TrpgMasterWeb.Chat.{Feed, Input, Messages}

  defdelegate dm_message(assigns), to: Messages
  defdelegate player_message(assigns), to: Messages
  defdelegate dice_result(assigns), to: Messages
  defdelegate tool_narration(assigns), to: Messages
  defdelegate system_message(assigns), to: Messages

  defdelegate chat_feed(assigns), to: Feed
  defdelegate typing_indicator(assigns), to: Feed

  defdelegate chat_input(assigns), to: Input
end
