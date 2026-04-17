defmodule TrpgMasterWeb.GameComponents do
  @moduledoc """
  게임 UI 컴포넌트: 채팅 메시지, 주사위 결과, 상태바.
  """
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  alias Phoenix.LiveView.JS

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
  상태 변경 도구(NPC 등록, 퀘스트 갱신, 위치 변경 등) 실행 시 채팅에 표시.
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
  캐릭터 상태바 컴포넌트.
  채팅 화면 하단에 HP, AC, 주문 슬롯, 현재 위치를 표시.
  """
  attr(:character, :map, default: nil)
  attr(:location, :string, default: nil)
  attr(:phase, :atom, default: :exploration)
  attr(:combat_state, :map, default: nil)
  attr(:mode, :atom, default: :adventure)

  def status_bar(assigns) do
    ~H"""
    <div class="status-bar">
      <%= if @character do %>
        <button phx-click={JS.show(to: "#character-modal")} class="char-sheet-btn" title="캐릭터 시트 열기">
          📜 <strong><%= @character["name"] || "캐릭터" %></strong>
        </button>
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
  캐릭터 시트 모달 컴포넌트.
  """
  attr(:character, :map, required: true)

  def character_sheet_modal(assigns) do
    ~H"""
    <div id="character-modal" style="display:none">
      <div class="character-modal-overlay" phx-click={JS.hide(to: "#character-modal")}></div>
      <div class="character-modal">
        <div class="char-modal-header">
          <div class="char-modal-title">
            <span class="char-modal-name"><%= @character["name"] || "캐릭터" %></span>
            <span class="char-modal-subtitle">
              <%= @character["class"] || "" %><%= if @character["subclass"], do: " (#{@character["subclass"]})", else: "" %><%= if @character["level"], do: " · #{@character["level"]}레벨", else: "" %>
            </span>
          </div>
          <button phx-click={JS.hide(to: "#character-modal")} class="modal-close-btn">✕</button>
        </div>

        <div class="char-modal-body">
          <div class="char-section">
            <div class="char-section-title">기본 정보</div>
            <div class="char-info-row">
              <%= if @character["race"] do %>
                <span class="char-info-item">종족 <strong><%= @character["race"] %></strong></span>
              <% end %>
              <%= if @character["subclass"] do %>
                <span class="char-info-item">서브클래스 <strong><%= @character["subclass"] %></strong></span>
              <% end %>
              <%= if @character["background"] do %>
                <span class="char-info-item">배경 <strong><%= @character["background"] %></strong></span>
              <% end %>
              <%= if @character["alignment"] do %>
                <span class="char-info-item">성향 <strong><%= @character["alignment"] %></strong></span>
              <% end %>
            </div>
          </div>

          <%= if @character["appearance"] && @character["appearance"] != "" do %>
            <div class="char-section">
              <div class="char-section-title">외모</div>
              <p class="char-prose"><%= @character["appearance"] %></p>
            </div>
          <% end %>

          <%= if @character["backstory"] && @character["backstory"] != "" do %>
            <div class="char-section">
              <div class="char-section-title">배경 스토리</div>
              <p class="char-prose"><%= @character["backstory"] %></p>
            </div>
          <% end %>

          <% abilities = @character["abilities"] || %{} %>
          <div class="char-section">
            <div class="char-section-title">능력치</div>
            <div class="char-ability-grid">
              <%= for {key, label} <- [{"str", "근력"}, {"dex", "민첩"}, {"con", "건강"}, {"int", "지능"}, {"wis", "지혜"}, {"cha", "매력"}] do %>
                <% score = abilities[key] %>
                <div class="char-ability-cell">
                  <span class="char-ability-label"><%= label %></span>
                  <span class="char-ability-score"><%= score || "—" %></span>
                  <span class="char-ability-mod"><%= ability_modifier(score) %></span>
                </div>
              <% end %>
            </div>
          </div>

          <div class="char-section">
            <div class="char-section-title">전투</div>
            <div class="char-combat-grid">
              <div class="char-combat-item">
                <span class="char-combat-label">HP</span>
                <span class="char-combat-value char-combat-hp">
                  <%= @character["hp_current"] || "?" %>/<%= @character["hp_max"] || "?" %>
                </span>
              </div>
              <div class="char-combat-item">
                <span class="char-combat-label">AC</span>
                <span class="char-combat-value char-combat-ac"><%= @character["ac"] || "?" %></span>
              </div>
              <%= if @character["speed"] do %>
                <div class="char-combat-item">
                  <span class="char-combat-label">이동</span>
                  <span class="char-combat-value"><%= @character["speed"] %>ft</span>
                </div>
              <% end %>
            </div>
          </div>

          <% slots = @character["spell_slots"] || %{} %>
          <% has_spells = Enum.any?(slots, fn {_, v} -> is_integer(v) && v > 0 end) %>
          <%= if has_spells do %>
            <% used = @character["spell_slots_used"] || %{} %>
            <div class="char-section">
              <div class="char-section-title">주문 슬롯</div>
              <div class="char-spell-slots">
                <%= for {level, total} <- Enum.sort(slots), is_integer(total) && total > 0 do %>
                  <% raw_used = used[level] %>
                  <% used_count = if is_integer(raw_used), do: raw_used, else: 0 %>
                  <div class="char-spell-slot-row">
                    <span class="char-spell-slot-level">Lv.<%= level %></span>
                    <div class="char-spell-slot-pips">
                      <%= for i <- 1..total do %>
                        <span class={"spell-pip #{if i <= used_count, do: "used", else: "available"}"}></span>
                      <% end %>
                    </div>
                    <span class="char-spell-slot-count"><%= total - used_count %>/<%= total %></span>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% spells_known = @character["spells_known"] || %{} %>
          <% has_known_spells = Enum.any?(spells_known, fn {_, v} -> is_list(v) && v != [] end) %>
          <%= if has_known_spells do %>
            <div class="char-section">
              <div class="char-section-title">알고 있는 주문</div>
              <div class="char-spells-known">
                <% cantrips = spells_known["cantrips"] || [] %>
                <%= if cantrips != [] do %>
                  <div class="char-spell-level-group">
                    <span class="char-spell-level-label">소마법</span>
                    <div class="char-spell-names">
                      <%= for spell <- cantrips do %>
                        <span class="char-spell-badge"><%= spell %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
                <%= for level_key <- ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do %>
                  <% level_spells = spells_known[level_key] || [] %>
                  <%= if level_spells != [] do %>
                    <div class="char-spell-level-group">
                      <span class="char-spell-level-label"><%= level_key %>레벨</span>
                      <div class="char-spell-names">
                        <%= for spell <- level_spells do %>
                          <span class="char-spell-badge"><%= spell %></span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>

          <% inventory = @character["inventory"] || [] %>
          <div class="char-section">
            <div class="char-section-title">소지품</div>
            <%= if inventory != [] do %>
              <div class="char-inventory-list">
                <%= for item <- inventory do %>
                  <div class="char-inventory-item">
                    <%= cond do
                      is_binary(item) -> item
                      is_map(item) -> item["name"] || "?"
                      true -> inspect(item)
                    end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <span class="char-empty-note">소지품 없음</span>
            <% end %>
          </div>

          <% class_features = @character["class_features"] || [] %>
          <%= if class_features != [] do %>
            <div class="char-section">
              <div class="char-section-title">클래스 피처</div>
              <div class="char-class-features">
                <%= for {lvl, features} <- class_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                  <div class="char-feature-level-group">
                    <span class="char-feature-level-label"><%= lvl %>레벨</span>
                    <div class="char-feature-names">
                      <%= for feature <- features do %>
                        <span class="char-feature-badge"><%= feature["name"] %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% subclass_features = @character["subclass_features"] || [] %>
          <%= if subclass_features != [] do %>
            <div class="char-section">
              <div class="char-section-title">서브클래스 피처 (<%= @character["subclass"] %>)</div>
              <div class="char-class-features">
                <%= for {lvl, features} <- subclass_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                  <div class="char-feature-level-group">
                    <span class="char-feature-level-label"><%= lvl %>레벨</span>
                    <div class="char-feature-names">
                      <%= for feature <- features do %>
                        <span class="char-feature-badge char-subclass-feature-badge"><%= feature["name"] %></span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <% feats = (@character["feats"] || []) ++ (if @character["background_feat"], do: [@character["background_feat"]], else: []) %>
          <%= if feats != [] do %>
            <div class="char-section">
              <div class="char-section-title">특기</div>
              <div class="char-features-list">
                <%= for feat_name <- feats do %>
                  <span class="char-feature-badge"><%= feat_name %></span>
                <% end %>
              </div>
            </div>
          <% end %>

          <% conditions = @character["conditions"] || [] %>
          <%= if conditions != [] do %>
            <div class="char-section">
              <div class="char-section-title">상태이상</div>
              <div class="char-conditions">
                <%= for condition_name <- conditions do %>
                  <span class="char-condition-badge"><%= condition_name %></span>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </div>
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
      {:ok, html, _warnings} ->
        html

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

  defp ability_modifier(nil), do: "+0"

  defp ability_modifier(score) when is_integer(score) do
    mod = Integer.floor_div(score - 10, 2)
    if mod >= 0, do: "+#{mod}", else: "#{mod}"
  end

  defp ability_modifier(_), do: "+0"

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
