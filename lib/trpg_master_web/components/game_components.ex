defmodule TrpgMasterWeb.GameComponents do
  @moduledoc """
  게임 UI 컴포넌트: 채팅 메시지, 주사위 결과, 상태바.
  """
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]

  @doc """
  DM 메시지 컴포넌트.
  """
  attr :text, :string, required: true

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
  attr :text, :string, required: true

  def player_message(assigns) do
    ~H"""
    <div class="message player-message">
      <div class="message-header">플레이어</div>
      <div class="message-body"><%= @text %></div>
    </div>
    """
  end

  @doc """
  주사위 결과 컴포넌트.
  """
  attr :result, :map, required: true

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
  시스템 메시지 컴포넌트.
  """
  attr :text, :string, required: true

  def system_message(assigns) do
    ~H"""
    <div class="message system-message">
      <span><%= @text %></span>
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

  # 텍스트의 줄바꿈을 <br>로 변환
  defp format_text(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>")
  end

  defp format_text(_), do: ""
end
