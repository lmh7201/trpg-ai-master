defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.AI.{Client, Models}

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Manager.start_campaign(campaign_id) do
      {:ok, _id} ->
        state = Server.get_state(campaign_id)
        messages = build_display_messages(state.conversation_history)
        current_model = state.ai_model || Models.default_model()

        {:ok,
         socket
         |> assign(:campaign_id, campaign_id)
         |> assign(:campaign_name, state.name)
         |> assign(:messages, messages)
         |> assign(:input_text, "")
         |> assign(:loading, false)
         |> assign(:error, nil)
         |> assign(:last_player_message, nil)
         |> assign(:current_location, state.current_location)
         |> assign(:phase, state.phase)
         |> assign(:character, List.first(state.characters))
         |> assign(:characters, state.characters)
         |> assign(:combat_state, state.combat_state)
         |> assign(:mode, state.mode)
         |> assign(:processing, false)
         |> assign(:ending_session, false)
         |> assign(:ai_model, current_model)
         |> assign(:show_model_selector, false)
         |> assign(:available_models, Models.list_with_status())}

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
      {:ok, result} ->
        messages =
          Enum.reduce(result.tool_results, socket.assigns.messages, fn tool_result, acc ->
            case tool_result do
              %{result: %{"formatted" => _} = dice_result} ->
                if socket.assigns.mode == :adventure && Map.get(tool_result.input || %{}, "hidden") do
                  acc
                else
                  acc ++ [%{type: :dice, result: dice_result}]
                end

              %{tool: tool_name, result: %{"status" => "ok", "message" => message}}
              when tool_name in ~w(register_npc update_quest set_location start_combat end_combat update_character write_journal) ->
                acc ++ [%{type: :tool_narration, tool_name: tool_name, message: message}]

              _ ->
                acc
            end
          end)

        messages = messages ++ [%{type: :dm, text: result.text}]
        state = Server.get_state(campaign_id)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)
         |> assign(:processing, false)
         |> assign(:current_location, state.current_location)
         |> assign(:phase, state.phase)
         |> assign(:character, List.first(state.characters))
         |> assign(:characters, state.characters)
         |> assign(:combat_state, state.combat_state)}

      {:error, reason} ->
        error_msg = Client.format_error(reason)

        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:processing, false)
         |> assign(:error, error_msg)}
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
            🤖 <%= model_short_name(@ai_model) %>
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

  defp build_display_messages(conversation_history) do
    conversation_history
    |> Enum.reduce([], fn msg, acc ->
      case msg do
        %{"role" => "user", "content" => content} when is_binary(content) ->
          acc ++ [%{type: :player, text: content}]

        %{"role" => "assistant", "content" => content} when is_binary(content) ->
          acc ++ [%{type: :dm, text: content}]

        _ ->
          acc
      end
    end)
  end

  defp phase_label(:exploration), do: "탐험"
  defp phase_label(:combat), do: "전투"
  defp phase_label(:dialogue), do: "대화"
  defp phase_label(:rest), do: "휴식"
  defp phase_label(_), do: "모험"

  defp model_short_name(model_id) do
    case Models.find(model_id) do
      nil -> model_id || "선택"
      model -> model.name
    end
  end
end
