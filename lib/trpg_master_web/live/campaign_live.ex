defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.AI.{Client, Models}
  alias TrpgMasterWeb.CampaignPresenter

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Manager.start_campaign(campaign_id) do
      {:ok, _id} ->
        state = Server.get_state(campaign_id)

        {:ok,
         socket
         |> assign(CampaignPresenter.mount_assigns(campaign_id, state))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "캠페인을 찾을 수 없습니다.")
         |> push_navigate(to: "/")}
    end
  end

  # ── 메시지 전송 ─────────────────────────────────────────────────────────────

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    message = String.trim(message)

    if message == "" || socket.assigns.processing do
      {:noreply, socket}
    else
      messages = socket.assigns.messages ++ [%{type: :player, text: message}]

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input_text, "")
        |> assign(:loading, true)
        |> assign(:processing, true)
        |> assign(:error, nil)
        |> assign(:last_player_message, message)

      send(self(), {:call_ai, message})
      {:noreply, socket}
    end
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  # ── 다시 시도 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("retry_last", _, socket) do
    case socket.assigns.last_player_message do
      nil ->
        {:noreply, socket}

      message ->
        socket =
          socket
          |> assign(:loading, true)
          |> assign(:error, nil)

        send(self(), {:call_ai, message})
        {:noreply, socket}
    end
  end

  # ── 모드 전환 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_mode", _, socket) do
    campaign_id = socket.assigns.campaign_id
    new_mode = if socket.assigns.mode == :adventure, do: :debug, else: :adventure

    Server.set_mode(campaign_id, new_mode)

    {:noreply, assign(socket, :mode, new_mode)}
  end

  # ── DM 선택 ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_model_selector", _, socket) do
    {:noreply, assign(socket, :show_model_selector, !socket.assigns.show_model_selector)}
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    campaign_id = socket.assigns.campaign_id

    if Models.api_key_configured?(model_id) do
      Server.set_model(campaign_id, model_id)
      model_info = Models.find(model_id)
      model_name = if model_info, do: model_info.name, else: model_id

      notice_msg = %{type: :system, text: "🤖 DM이 #{model_name}(으)로 변경되었습니다."}
      messages = socket.assigns.messages ++ [notice_msg]

      {:noreply,
       socket
       |> assign(:ai_model, model_id)
       |> assign(:show_model_selector, false)
       |> assign(:messages, messages)}
    else
      model_info = Models.find(model_id)
      env_var = if model_info, do: model_info.env, else: "API 키"

      notice_msg = %{
        type: :system,
        text: "⚠️ #{env_var} 환경변수가 설정되지 않았습니다. 서버 관리자에게 문의하세요."
      }

      messages = socket.assigns.messages ++ [notice_msg]

      {:noreply,
       socket
       |> assign(:show_model_selector, false)
       |> assign(:messages, messages)}
    end
  end

  # ── 세션 종료 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("end_session", _, socket) do
    socket =
      socket
      |> assign(:ending_session, true)
      |> assign(:loading, true)

    send(self(), :do_end_session)

    {:noreply, socket}
  end

  # ── AI 호출 (info) ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:call_ai, message}, socket) do
    campaign_id = socket.assigns.campaign_id

    case Server.player_action(campaign_id, message) do
      # 전투 모드: 리스트 반환 [player_result | enemy_results]
      {:ok, [player_result | enemy_results]} when enemy_results != [] ->
        messages =
          CampaignPresenter.append_tool_messages(
            socket.assigns.messages,
            socket.assigns.mode,
            player_result
          )

        messages = messages ++ [%{type: :dm, text: player_result.text}]
        state = Server.get_state(campaign_id)

        # 플레이어 턴 결과 즉시 표시, 적 그룹 턴들은 순차 표시
        send(self(), {:display_enemy_turns, enemy_results})

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, true)
         |> assign(CampaignPresenter.state_assigns(state))}

      # 탐험 모드 또는 단일 결과 (전투 종료 시 등)
      {:ok, result} when not is_list(result) ->
        messages =
          CampaignPresenter.append_tool_messages(
            socket.assigns.messages,
            socket.assigns.mode,
            result
          )

        messages = messages ++ [%{type: :dm, text: result.text}]
        state = Server.get_state(campaign_id)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)
         |> assign(:processing, false)
         |> assign(CampaignPresenter.state_assigns(state))}

      {:error, reason} ->
        error_msg = Client.format_error(reason)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:processing, false)
         |> assign(:error, error_msg)}
    end
  end

  # 적 그룹 턴 순차 표시 — 남은 적 그룹이 있으면 계속 체이닝
  @impl true
  def handle_info({:display_enemy_turns, [result | rest]}, socket) do
    campaign_id = socket.assigns.campaign_id

    messages =
      CampaignPresenter.append_tool_messages(socket.assigns.messages, socket.assigns.mode, result)

    messages = messages ++ [%{type: :dm, text: result.text}]

    if rest == [] do
      # 마지막 적 그룹 — 로딩 종료
      state = Server.get_state(campaign_id)

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:loading, false)
       |> assign(:processing, false)
       |> assign(CampaignPresenter.state_assigns(state))}
    else
      # 다음 적 그룹 표시 예약
      state = Server.get_state(campaign_id)
      send(self(), {:display_enemy_turns, rest})

      {:noreply,
       socket
       |> assign(:messages, messages)
       |> assign(:loading, true)
       |> assign(CampaignPresenter.state_assigns(state))}
    end
  end

  @impl true
  def handle_info(:do_end_session, socket) do
    campaign_id = socket.assigns.campaign_id

    case Server.end_session(campaign_id) do
      {:ok, summary_text} ->
        messages =
          socket.assigns.messages ++
            [
              %{type: :system, text: "📋 세션이 종료되었습니다. 대화 기록이 저장되었습니다."},
              %{type: :dm, text: summary_text}
            ]

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)
         |> assign(:ending_session, false)}

      {:error, reason} ->
        error_msg = Client.format_error(reason)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:ending_session, false)
         |> assign(:error, "세션 종료 실패: #{error_msg}")}
    end
  end

  # ── Render ───────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="game-container">
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

      <%= if @show_model_selector do %>
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
      <% end %>

      <%= if @character do %>
        <div id="character-modal" style="display:none">
        <div class="character-modal-overlay" phx-click={JS.hide(to: "#character-modal")}></div>
        <div class="character-modal">
          <%!-- 헤더 --%>
          <div class="char-modal-header">
            <div class="char-modal-title">
              <span class="char-modal-name"><%= @character["name"] || "캐릭터" %></span>
              <span class="char-modal-subtitle">
                <%= @character["class"] || "" %><%= if @character["subclass"], do: " (#{@character["subclass"]})", else: "" %><%= if @character["level"], do: " · #{@character["level"]}레벨", else: "" %>
              </span>
            </div>
            <button phx-click={JS.hide(to: "#character-modal")} class="modal-close-btn">✕</button>
          </div>

          <%!-- 바디 --%>
          <div class="char-modal-body">

            <%!-- 기본 정보 --%>
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

            <%!-- 외모 --%>
            <%= if @character["appearance"] && @character["appearance"] != "" do %>
              <div class="char-section">
                <div class="char-section-title">외모</div>
                <p class="char-prose"><%= @character["appearance"] %></p>
              </div>
            <% end %>

            <%!-- 배경 스토리 --%>
            <%= if @character["backstory"] && @character["backstory"] != "" do %>
              <div class="char-section">
                <div class="char-section-title">배경 스토리</div>
                <p class="char-prose"><%= @character["backstory"] %></p>
              </div>
            <% end %>

            <%!-- 능력치 --%>
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

            <%!-- 전투 스탯 --%>
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

            <%!-- 주문 슬롯 (해당 클래스만) --%>
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

            <%!-- 알고 있는 주문 --%>
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

            <%!-- 소지품 --%>
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

            <%!-- 클래스 피처 (있을 때만) --%>
            <% class_features = @character["class_features"] || [] %>
            <%= if class_features != [] do %>
              <div class="char-section">
                <div class="char-section-title">클래스 피처</div>
                <div class="char-class-features">
                  <%= for {lvl, features} <- class_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                    <div class="char-feature-level-group">
                      <span class="char-feature-level-label"><%= lvl %>레벨</span>
                      <div class="char-feature-names">
                        <%= for f <- features do %>
                          <span class="char-feature-badge"><%= f["name"] %></span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- 서브클래스 피처 (있을 때만) --%>
            <% subclass_features = @character["subclass_features"] || [] %>
            <%= if subclass_features != [] do %>
              <div class="char-section">
                <div class="char-section-title">서브클래스 피처 (<%= @character["subclass"] %>)</div>
                <div class="char-class-features">
                  <%= for {lvl, features} <- subclass_features |> Enum.group_by(& &1["level"]) |> Enum.sort() do %>
                    <div class="char-feature-level-group">
                      <span class="char-feature-level-label"><%= lvl %>레벨</span>
                      <div class="char-feature-names">
                        <%= for f <- features do %>
                          <span class="char-feature-badge char-subclass-feature-badge"><%= f["name"] %></span>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <%!-- 특기 (있을 때만) --%>
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

            <%!-- 상태이상 (있을 때만) --%>
            <% conditions = @character["conditions"] || [] %>
            <%= if conditions != [] do %>
              <div class="char-section">
                <div class="char-section-title">상태이상</div>
                <div class="char-conditions">
                  <%= for cond_name <- conditions do %>
                    <span class="char-condition-badge"><%= cond_name %></span>
                  <% end %>
                </div>
              </div>
            <% end %>

          </div>
        </div>
        </div>
      <% end %>

      <div class="chat-area" id="chat-area" phx-hook="ScrollBottom">
        <%= if @messages == [] do %>
          <div class="welcome-message">
            <.system_message text="AI 던전 마스터에 오신 것을 환영합니다! 메시지를 입력하여 모험을 시작하세요." />
          </div>
        <% end %>

        <%= for msg <- @messages do %>
          <%= case msg.type do %>
            <% :dm -> %>
              <.dm_message text={msg.text} />
            <% :player -> %>
              <.player_message text={msg.text} name={if @character, do: @character["name"] || "플레이어", else: "플레이어"} />
            <% :dice -> %>
              <.dice_result result={msg.result} />
            <% :tool_narration -> %>
              <.tool_narration tool_name={msg.tool_name} message={msg.message} />
            <% :system -> %>
              <.system_message text={msg.text} />
          <% end %>
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

      <%= if length(@characters) > 1 do %>
        <%= for char <- @characters do %>
          <.status_bar
            character={char}
            location={@current_location}
            phase={@phase}
            combat_state={@combat_state}
            mode={@mode}
          />
        <% end %>
      <% else %>
        <.status_bar
          character={@character}
          location={@current_location}
          phase={@phase}
          combat_state={@combat_state}
          mode={@mode}
        />
      <% end %>

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
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

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

  defp provider_icon(model_id) do
    svg =
      case Models.provider_for(model_id) do
        :anthropic ->
          # Anthropic / Claude — simplified "A" lettermark, coral colour
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Claude">
            <path d="M13.83 3.52h-3.62L5.08 20.48h3.46l1.07-3.04h4.78l1.07 3.04h3.46L13.83 3.52zm-3.33 11.25 1.57-4.47 1.57 4.47H10.5z" fill="#D97757"/>
          </svg>
          """

        :openai ->
          # OpenAI / GPT — four-pointed star polygon, green
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="GPT">
            <path d="M22.28 9.82a5.98 5.98 0 0 0-.52-4.91 6.05 6.05 0 0 0-6.51-2.9A6.07 6.07 0 0 0 4.98 4.18a5.98 5.98 0 0 0-3.99 2.9 6.05 6.05 0 0 0 .74 7.1 5.98 5.98 0 0 0 .51 4.91 6.05 6.05 0 0 0 6.51 2.9A5.98 5.98 0 0 0 13.26 24a6.06 6.06 0 0 0 5.77-4.21 5.99 5.99 0 0 0 4-2.9 6.06 6.06 0 0 0-.75-7.07zM13.26 22.5a4.48 4.48 0 0 1-2.88-1.04l.14-.08 4.78-2.76a.79.79 0 0 0 .4-.68V11.2l2.02 1.17a.07.07 0 0 1 .04.05v5.58a4.5 4.5 0 0 1-4.5 4.5zM3.6 18.37a4.47 4.47 0 0 1-.53-3.01l.14.08 4.78 2.76a.77.77 0 0 0 .78 0l5.84-3.37v2.33a.08.08 0 0 1-.03.06L9.74 19.95A4.5 4.5 0 0 1 3.6 18.37zM2.34 7.9a4.49 4.49 0 0 1 2.37-1.97v5.65a.77.77 0 0 0 .39.68l5.81 3.35-2.02 1.17a.08.08 0 0 1-.07 0L3.55 13.9A4.5 4.5 0 0 1 2.34 7.89zm16.6 3.86-5.84-3.37 2.02-1.17a.08.08 0 0 1 .07 0l4.83 2.79a4.49 4.49 0 0 1-.68 8.1V12.44a.79.79 0 0 0-.4-.68zm2.01-3.02-.14-.09-4.77-2.78a.78.78 0 0 0-.79 0L9.41 9.23V6.9a.07.07 0 0 1 .03-.06l4.83-2.79a4.5 4.5 0 0 1 6.68 4.66zM8.31 12.86 6.29 11.7a.08.08 0 0 1-.04-.06V6.07a4.5 4.5 0 0 1 7.38-3.45l-.14.08-4.78 2.76a.79.79 0 0 0-.4.68v6.72zm1.1-2.37 2.6-1.5 2.61 1.5v3L12 15l-2.6-1.5V10.5z" fill="#10A37F"/>
          </svg>
          """

        :gemini ->
          # Google Gemini — four-pointed star, blue-to-purple gradient
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

    Phoenix.HTML.raw(svg)
  end
end
