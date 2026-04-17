defmodule TrpgMasterWeb.GameComponents do
  @moduledoc """
  게임 UI 컴포넌트: 채팅 메시지, 주사위 결과, 상태바.
  """
  use Phoenix.Component
  import Phoenix.HTML, only: [raw: 1]
  alias Phoenix.LiveView.JS
  alias TrpgMaster.AI.Models

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
  캠페인 화면 상단 헤더 컴포넌트.
  """
  attr(:campaign_id, :string, required: true)
  attr(:campaign_name, :string, required: true)
  attr(:phase, :atom, default: :exploration)
  attr(:ai_model, :string, required: true)
  attr(:mode, :atom, default: :adventure)
  attr(:loading, :boolean, default: false)

  def campaign_header(assigns) do
    ~H"""
    <header class="game-header">
      <div class="header-left">
        <a href="/" class="back-link">←</a>
        <h1><%= @campaign_name %></h1>
      </div>
      <div class="header-right">
        <span class="mode-badge"><%= phase_label(@phase) %></span>
        <button phx-click="toggle_model_selector" class="dm-select-btn" title="DM 선택">
          <%= provider_icon(@ai_model) %>
        </button>
        <button phx-click="toggle_mode" class={"mode-toggle #{if @mode == :debug, do: "mode-debug", else: "mode-adventure"}"} title={if @mode == :adventure, do: "디버그 모드로 전환", else: "모험 모드로 전환"}>
          <%= if @mode == :adventure do %>🎭<% else %>🔧<% end %>
        </button>
        <a href={"/history/#{@campaign_id}"} class="history-btn" title="모험 기록 보기">
          📖
        </a>
        <button phx-click="end_session" class="end-session-btn" title="세션 종료" disabled={@loading}>
          📋
        </button>
      </div>
    </header>
    """
  end

  @doc """
  DM 모델 선택 모달 컴포넌트.
  """
  attr(:available_models, :list, required: true)
  attr(:ai_model, :string, required: true)

  def model_selector_modal(assigns) do
    ~H"""
    <div>
      <div class="model-selector-overlay" phx-click="toggle_model_selector"></div>
      <div class="model-selector-modal">
        <div class="model-selector-header">
          <h3>🤖 DM 선택</h3>
          <button phx-click="toggle_model_selector" class="modal-close-btn">✕</button>
        </div>
        <div class="model-selector-list">
          <%= for provider <- [:anthropic, :openai, :gemini] do %>
            <div class="model-provider-group">
              <div class="model-provider-label"><%= Models.provider_label(provider) %></div>
              <%= for model <- Enum.filter(@available_models, &(&1.provider == provider)) do %>
                <button
                  class={"model-option #{if model.id == @ai_model, do: "model-option-active", else: ""} #{if not model.available, do: "model-option-disabled", else: ""}"}
                  phx-click="select_model"
                  phx-value-model={model.id}
                  title={unless model.available, do: "#{model.env} 환경변수가 설정되지 않았습니다.", else: ""}
                >
                  <span class="model-option-name"><%= model.name %></span>
                  <%= if model.id == @ai_model do %>
                    <span class="model-option-badge model-badge-active">사용 중</span>
                  <% end %>
                  <%= unless model.available do %>
                    <span class="model-option-badge model-badge-unavailable">API 키 미설정</span>
                  <% end %>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
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

  defp phase_label(:exploration), do: "탐험"
  defp phase_label(:combat), do: "전투"
  defp phase_label(:dialogue), do: "대화"
  defp phase_label(:rest), do: "휴식"
  defp phase_label(_), do: "모험"

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

  defp provider_icon(model_id) do
    svg =
      case Models.provider_for(model_id) do
        :anthropic ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Claude">
            <path d="M13.83 3.52h-3.62L5.08 20.48h3.46l1.07-3.04h4.78l1.07 3.04h3.46L13.83 3.52zm-3.33 11.25 1.57-4.47 1.57 4.47H10.5z" fill="#D97757"/>
          </svg>
          """

        :openai ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="GPT">
            <path d="M22.28 9.82a5.98 5.98 0 0 0-.52-4.91 6.05 6.05 0 0 0-6.51-2.9A6.07 6.07 0 0 0 4.98 4.18a5.98 5.98 0 0 0-3.99 2.9 6.05 6.05 0 0 0 .74 7.1 5.98 5.98 0 0 0 .51 4.91 6.05 6.05 0 0 0 6.51 2.9A5.98 5.98 0 0 0 13.26 24a6.06 6.06 0 0 0 5.77-4.21 5.99 5.99 0 0 0 4-2.9 6.06 6.06 0 0 0-.75-7.07zM13.26 22.5a4.48 4.48 0 0 1-2.88-1.04l.14-.08 4.78-2.76a.79.79 0 0 0 .4-.68V11.2l2.02 1.17a.07.07 0 0 1 .04.05v5.58a4.5 4.5 0 0 1-4.5 4.5zM3.6 18.37a4.47 4.47 0 0 1-.53-3.01l.14.08 4.78 2.76a.77.77 0 0 0 .78 0l5.84-3.37v2.33a.08.08 0 0 1-.03.06L9.74 19.95A4.5 4.5 0 0 1 3.6 18.37zM2.34 7.9a4.49 4.49 0 0 1 2.37-1.97v5.65a.77.77 0 0 0 .39.68l5.81 3.35-2.02 1.17a.08.08 0 0 1-.07 0L3.55 13.9A4.5 4.5 0 0 1 2.34 7.89zm16.6 3.86-5.84-3.37 2.02-1.17a.08.08 0 0 1 .07 0l4.83 2.79a4.49 4.49 0 0 1-.68 8.1V12.44a.79.79 0 0 0-.4-.68zm2.01-3.02-.14-.09-4.77-2.78a.78.78 0 0 0-.79 0L9.41 9.23V6.9a.07.07 0 0 1 .03-.06l4.83-2.79a4.5 4.5 0 0 1 6.68 4.66zM8.31 12.86 6.29 11.7a.08.08 0 0 1-.04-.06V6.07a4.5 4.5 0 0 1 7.38-3.45l-.14.08-4.78 2.76a.79.79 0 0 0-.4.68v6.72zm1.1-2.37 2.6-1.5 2.61 1.5v3L12 15l-2.6-1.5V10.5z" fill="#10A37F"/>
          </svg>
          """

        :gemini ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Gemini">
            <defs>
              <linearGradient id="gemini-grad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#4285F4"/>
                <stop offset="100%" stop-color="#8B5CF6"/>
              </linearGradient>
            </defs>
            <path d="M12 24A14.3 14.3 0 0 1 0 12 14.3 14.3 0 0 1 12 0a14.3 14.3 0 0 1 12 12 14.3 14.3 0 0 1-12 12z" fill="url(#gemini-grad)"/>
            <path d="M12 22A12.3 12.3 0 0 0 2 12 12.3 12.3 0 0 0 12 2a12.3 12.3 0 0 0 10 10 12.3 12.3 0 0 0-10 10z" fill="white"/>
          </svg>
          """

        _ ->
          "<span style=\"font-size:1.1rem\">🤖</span>"
      end

    raw(svg)
  end
end
