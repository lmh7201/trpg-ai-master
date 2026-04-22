defmodule TrpgMasterWeb.Chat.Feed do
  @moduledoc false

  use TrpgMasterWeb, :html

  import TrpgMasterWeb.Chat.Messages,
    only: [
      dm_message: 1,
      player_message: 1,
      dice_result: 1,
      tool_narration: 1,
      system_message: 1
    ]

  @doc """
  캠페인 채팅 피드 컴포넌트.
  """
  attr(:messages, :list, required: true)
  attr(:character, :map, default: nil)
  attr(:ending_session, :boolean, default: false)
  attr(:loading, :boolean, default: false)
  attr(:error, :string, default: nil)
  attr(:last_player_message, :string, default: nil)

  def chat_feed(assigns) do
    ~H"""
    <div class="chat-area" id="chat-area" phx-hook="ScrollBottom">
      <%= if @messages == [] do %>
        <div class="welcome-message">
          <.system_message text="AI 던전 마스터에 오신 것을 환영합니다! 메시지를 입력하여 모험을 시작하세요." />
        </div>
      <% end %>

      <%= for msg <- @messages do %>
        <.chat_message msg={msg} player_name={player_name(@character)} />
      <% end %>

      <%= if @ending_session do %>
        <.system_message text="📋 세션 요약을 생성 중입니다..." />
      <% end %>

      <%= if @loading && !@ending_session do %>
        <.typing_indicator />
      <% end %>

      <%= if @error do %>
        <div class="message error-message">
          <span>⚠️ <%= @error %></span>
          <%= if @last_player_message do %>
            <button phx-click="retry_last" class="retry-btn">다시 시도</button>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  타이핑 인디케이터.
  """
  def typing_indicator(assigns) do
    ~H"""
    <div class="message dm-message typing">
      <div class="message-header">DM</div>
      <div class="message-body">
        <span class="typing-dots">
          <span>.</span><span>.</span><span>.</span>
        </span>
      </div>
    </div>
    """
  end

  # ── Private ──────────────────────────────────────────────────────────────

  attr(:msg, :map, required: true)
  attr(:player_name, :string, required: true)

  defp chat_message(assigns) do
    ~H"""
    <%= case @msg.type do %>
      <% :dm -> %>
        <.dm_message text={@msg.text} />
      <% :player -> %>
        <.player_message text={@msg.text} name={@player_name} />
      <% :dice -> %>
        <.dice_result result={@msg.result} />
      <% :tool_narration -> %>
        <.tool_narration tool_name={@msg.tool_name} message={@msg.message} />
      <% :system -> %>
        <.system_message text={@msg.text} />
    <% end %>
    """
  end

  defp player_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp player_name(_), do: "플레이어"
end
