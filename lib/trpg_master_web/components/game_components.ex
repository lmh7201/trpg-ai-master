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
  attr :name, :string, default: "플레이어"

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
  도구 호출 결과 알림 컴포넌트.
  상태 변경 도구(NPC 등록, 퀘스트 갱신, 위치 변경 등) 실행 시 채팅에 표시.
  """
  attr :tool_name, :string, required: true
  attr :message, :string, required: true

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
  attr :text, :string, required: true

  def system_message(assigns) do
    ~H"""
    <div class="message system-message">
      <span><%= @text %></span>
    </div>
    """
  end

  @doc """
  캐릭터 상태바 컴포넌트.
  채팅 화면 하단에 HP, AC, 주문 슬롯, 현재 위치를 표시.
  """
  attr :character, :map, default: nil
  attr :location, :string, default: nil
  attr :phase, :atom, default: :exploration
  attr :combat_state, :map, default: nil
  attr :mode, :atom, default: :adventure

  def status_bar(assigns) do
    ~H"""
    <div class="status-bar">
      <%= if @character do %>
        <span class="status-item">
          ❤️ <strong><%= @character["hp_current"] || "?" %>/<%= @character["hp_max"] || "?" %></strong>
        </span>
        <%= if @character["ac"] do %>
          <span class="status-item">🛡️ AC <strong><%= @character["ac"] %></strong></span>
        <% end %>
        <%= if spell_slot_total(@character) > 0 do %>
          <span class="status-item">⚡ <strong><%= spell_slots_display(@character) %></strong></span>
        <% end %>
      <% end %>
      <span class="status-item">📍 <%= @location || "미정" %></span>
      <%= if @phase == :combat && @combat_state do %>
        <span class="status-item combat-badge">
          ⚔️ <strong><%= @combat_state["round"] || 1 %>라운드</strong>
          <%= if @combat_state["participants"] do %>
            — <%= Enum.join(@combat_state["participants"], " vs ") %>
          <% end %>
        </span>
      <% end %>
      <%= if @mode == :debug do %>
        <span class="status-item debug-badge">🔧 디버그</span>
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

  # 마크다운을 HTML로 변환 (Earmark 사용)
  defp format_text(text) when is_binary(text) do
    # Earmark은 내부적으로 HTML 이스케이프를 처리하므로 안전
    case Earmark.as_html(text, %Earmark.Options{breaks: true}) do
      {:ok, html, _warnings} -> html
      {:error, _, _} ->
        text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp format_text(_), do: ""

  # 주문 슬롯 표시 (예: "1/3")
  defp spell_slots_display(character) do
    slots = character["spell_slots"] || %{}
    used = character["spell_slots_used"] || %{}
    total = spell_slot_total(character)

    used_count =
      used
      |> Enum.map(fn {_k, v} -> if is_integer(v), do: v, else: 0 end)
      |> Enum.sum()

    total_count =
      slots
      |> Enum.map(fn {_k, v} -> if is_integer(v), do: v, else: 0 end)
      |> Enum.sum()

    if total > 0 do
      "주문 슬롯 #{total_count - used_count}/#{total_count}"
    else
      ""
    end
  end

  defp tool_icon("register_npc"), do: "📋"
  defp tool_icon("update_quest"), do: "📜"
  defp tool_icon("set_location"), do: "📍"
  defp tool_icon("start_combat"), do: "⚔️"
  defp tool_icon("end_combat"), do: "🏁"
  defp tool_icon("update_character"), do: "👤"
  defp tool_icon("write_journal"), do: "📝"
  defp tool_icon(_), do: "🔧"

  defp spell_slot_total(character) do
    slots = character["spell_slots"] || %{}

    slots
    |> Enum.map(fn {_k, v} -> if is_integer(v), do: v, else: 0 end)
    |> Enum.sum()
  end
end
