defmodule TrpgMasterWeb.ChatComponents do
  @moduledoc """
  캠페인 채팅 메시지, 피드, 입력 폼을 담당하는 컴포넌트 모음.
  """

  use TrpgMasterWeb, :html

  @doc """
  DM 메시지 컴포넌트.
  """
  attr(:text, :string, required: true)

  def dm_message(assigns) do
    ~H"""
    <div class="message dm-message">
      <div class="message-header">DM</div>
      <div class="message-body"><%= raw(format_text(@text)) %></div>
    </div>
    """
  end

  @doc """
  플레이어 메시지 컴포넌트.
  """
  attr(:text, :string, required: true)
  attr(:name, :string, default: "플레이어")

  def player_message(assigns) do
    ~H"""
    <div class="message player-message">
      <div class="message-header"><%= @name %></div>
      <div class="message-body"><%= @text %></div>
    </div>
    """
  end

  @doc """
  주사위 결과 컴포넌트.
  """
  attr(:result, :map, required: true)

  def dice_result(assigns) do
    ~H"""
    <div class="message dice-message">
      <span class="dice-icon">🎲</span>
      <span class="dice-text"><%= @result["formatted"] %></span>
      <span :if={@result["natural_20"]} class="dice-crit">크리티컬!</span>
      <span :if={@result["natural_1"]} class="dice-fumble">펌블!</span>
    </div>
    """
  end

  @doc """
  도구 호출 결과 알림 컴포넌트.
  """
  attr(:tool_name, :string, required: true)
  attr(:message, :string, required: true)

  def tool_narration(assigns) do
    ~H"""
    <div class="message tool-narration-message">
      <span class="tool-icon"><%= tool_icon(@tool_name) %></span>
      <span class="tool-text"><%= @message %></span>
    </div>
    """
  end

  @doc """
  시스템 메시지 컴포넌트.
  """
  attr(:text, :string, required: true)

  def system_message(assigns) do
    ~H"""
    <div class="message system-message">
      <span><%= @text %></span>
    </div>
    """
  end

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
  채팅 입력 폼 컴포넌트.
  """
  attr(:input_text, :string, default: "")
  attr(:loading, :boolean, default: false)
  attr(:processing, :boolean, default: false)

  def chat_input(assigns) do
    ~H"""
    <form class="input-area" phx-submit="send_message" id="message-form">
      <textarea
        name="message"
        placeholder={if @processing, do: "DM이 응답을 준비하는 중...", else: "무엇을 하시겠습니까? (Shift+Enter로 줄바꿈)"}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        spellcheck="false"
        disabled={@loading || @processing}
        rows="1"
        phx-hook="AutoResize"
        id="message-input"
      ><%= @input_text %></textarea>
      <button type="submit" disabled={@loading} aria-label="전송">
        <span>↑</span>
      </button>
    </form>
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

  defp format_text(text) when is_binary(text) do
    case Earmark.as_html(text, %Earmark.Options{breaks: true}) do
      {:ok, html, _warnings} ->
        html

      {:error, _, _} ->
        text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp format_text(_), do: ""

  defp tool_icon("register_npc"), do: "📋"
  defp tool_icon("update_quest"), do: "📜"
  defp tool_icon("set_location"), do: "📍"
  defp tool_icon("start_combat"), do: "⚔️"
  defp tool_icon("end_combat"), do: "🏁"
  defp tool_icon("update_character"), do: "👤"
  defp tool_icon("write_journal"), do: "📝"
  defp tool_icon(_), do: "🔧"
end
