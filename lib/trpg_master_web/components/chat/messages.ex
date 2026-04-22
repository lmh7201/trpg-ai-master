defmodule TrpgMasterWeb.Chat.Messages do
  @moduledoc false

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

  # ── Helpers ───────────────────────────────────────────────────────────────

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
