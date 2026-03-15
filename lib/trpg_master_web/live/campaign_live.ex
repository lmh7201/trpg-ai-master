defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMaster.AI.Client

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Manager.start_campaign(campaign_id) do
      {:ok, _id} ->
        state = Server.get_state(campaign_id)
        messages = build_display_messages(state.conversation_history)

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
         |> assign(:ending_session, false)}

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
                # 모험 모드에서 hidden 주사위 결과 숨김
                if socket.assigns.mode == :adventure && Map.get(tool_result.input || %{}, "hidden") do
                  acc
                else
                  acc ++ [%{type: :dice, result: dice_result}]
                end

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
          <span :if={@current_location} class="location-badge"><%= @current_location %></span>
          <span class="mode-badge"><%= phase_label(@phase) %></span>
          <button phx-click="toggle_mode" class={"mode-toggle #{if @mode == :debug, do: "mode-debug", else: "mode-adventure"}"} title={if @mode == :adventure, do: "디버그 모드로 전환", else: "모험 모드로 전환"}>
            <%= if @mode == :adventure do %>🎭<% else %>🔧<% end %>
          </button>
          <button phx-click="end_session" class="end-session-btn" title="세션 종료" disabled={@loading}>
            📋
          </button>
        </div>
      </header>

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
end
