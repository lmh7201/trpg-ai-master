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

  # 마크다운을 HTML로 변환
  defp format_text(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> markdown_to_html()
  end

  defp format_text(_), do: ""

  defp markdown_to_html(text) do
    text
    |> String.split("\n")
    |> parse_lines()
    |> Enum.join("\n")
  end

  defp parse_lines(lines) do
    {result, acc} = Enum.reduce(lines, {[], nil}, fn line, {result, list_state} ->
      cond do
        # 수평선
        Regex.match?(~r/^(---|\*\*\*|___)$/, line) ->
          {flush_list(result, list_state) ++ ["<hr>"], nil}

        # 헤더 (## 또는 ###)
        Regex.match?(~r/^\#{1,6} /, line) ->
          [hashes | rest] = String.split(line, " ", parts: 2)
          level = min(String.length(hashes), 6)
          tag = "h#{level}"
          content = List.first(rest) |> inline_format()
          {flush_list(result, list_state) ++ ["<#{tag}>#{content}</#{tag}>"], nil}

        # 불릿 리스트 항목
        Regex.match?(~r/^[-*] /, line) ->
          item = String.slice(line, 2..-1//1) |> inline_format()
          {result, (list_state || []) ++ ["<li>#{item}</li>"]}

        # 빈 줄
        String.trim(line) == "" ->
          {flush_list(result, list_state), nil}

        # 일반 텍스트
        true ->
          {flush_list(result, list_state) ++ ["<p>#{inline_format(line)}</p>"], nil}
      end
    end)

    flush_list(result, acc)
  end

  defp flush_list(result, nil), do: result
  defp flush_list(result, items), do: result ++ ["<ul>" <> Enum.join(items) <> "</ul>"]

  defp inline_format(text) do
    text
    # bold + italic: ***text***
    |> String.replace(~r/\*\*\*(.+?)\*\*\*/, "<strong><em>\\1</em></strong>")
    # bold: **text**
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    # italic: *text* (단어 경계 처리)
    |> String.replace(~r/\*([^\*]+)\*/, "<em>\\1</em>")
    # italic: _text_
    |> String.replace(~r/_([^_]+)_/, "<em>\\1</em>")
    # 코드: `text`
    |> String.replace(~r/`([^`]+)`/, "<code>\\1</code>")
  end

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

  defp spell_slot_total(character) do
    slots = character["spell_slots"] || %{}

    slots
    |> Enum.map(fn {_k, v} -> if is_integer(v), do: v, else: 0 end)
    |> Enum.sum()
  end
end
