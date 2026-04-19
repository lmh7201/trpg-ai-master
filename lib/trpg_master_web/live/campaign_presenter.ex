defmodule TrpgMasterWeb.CampaignPresenter do
  @moduledoc """
  CampaignLive의 화면용 상태 조립과 메시지 변환을 담당한다.
  """

  alias TrpgMasterWeb.CampaignPresenter.{State, ToolMessages}

  defdelegate mount_assigns(campaign_id, state), to: State
  defdelegate state_assigns(state), to: State
  defdelegate append_tool_messages(messages, mode, result), to: ToolMessages, as: :append
end
