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
      <.campaign_header
        campaign_id={@campaign_id}
        campaign_name={@campaign_name}
        phase={@phase}
        ai_model={@ai_model}
        mode={@mode}
        loading={@loading}
      />

      <%= if @show_model_selector do %>
        <.model_selector_modal available_models={@available_models} ai_model={@ai_model} />
      <% end %>

      <%= if @character do %>
        <.character_sheet_modal character={@character} />
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
end
