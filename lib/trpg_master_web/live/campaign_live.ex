defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.ChatComponents
  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.Campaign.{Manager, Server}
  alias TrpgMasterWeb.{CampaignFlow, CampaignPresenter}

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
    case CampaignFlow.submit_message(socket.assigns, message) do
      {:ok, updates, trimmed_message} ->
        send(self(), {:call_ai, trimmed_message})
        {:noreply, assign(socket, updates)}

      :ignore ->
        {:noreply, socket}
    end
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  # ── 다시 시도 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("retry_last", _, socket) do
    case CampaignFlow.retry_last(socket.assigns) do
      {:ok, updates, message} ->
        send(self(), {:call_ai, message})
        {:noreply, assign(socket, updates)}

      :ignore ->
        {:noreply, socket}
    end
  end

  # ── 모드 전환 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_mode", _, socket) do
    campaign_id = socket.assigns.campaign_id
    new_mode = CampaignFlow.next_mode(socket.assigns.mode)

    Server.set_mode(campaign_id, new_mode)

    {:noreply, assign(socket, :mode, new_mode)}
  end

  # ── DM 선택 ─────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("toggle_model_selector", _, socket) do
    {:noreply, assign(socket, CampaignFlow.toggle_model_selector(socket.assigns))}
  end

  @impl true
  def handle_event("select_model", %{"model" => model_id}, socket) do
    campaign_id = socket.assigns.campaign_id

    case CampaignFlow.select_model(socket.assigns, model_id) do
      {:ok, updates} ->
        Server.set_model(campaign_id, model_id)
        {:noreply, assign(socket, updates)}

      {:error, updates} ->
        {:noreply, assign(socket, updates)}
    end
  end

  # ── 세션 종료 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("end_session", _, socket) do
    send(self(), :do_end_session)

    {:noreply, assign(socket, CampaignFlow.begin_end_session())}
  end

  # ── AI 호출 (info) ───────────────────────────────────────────────────────────

  @impl true
  def handle_info({:call_ai, message}, socket) do
    campaign_id = socket.assigns.campaign_id

    case Server.player_action(campaign_id, message) do
      {:ok, [player_result | enemy_results]} when enemy_results != [] ->
        state = Server.get_state(campaign_id)

        case CampaignFlow.apply_player_action_result(
               socket.assigns,
               [player_result | enemy_results],
               state
             ) do
          {:enemy_turns, updates, rest} ->
            send(self(), {:display_enemy_turns, rest})
            {:noreply, assign(socket, updates)}
        end

      {:ok, result} when not is_list(result) ->
        state = Server.get_state(campaign_id)

        case CampaignFlow.apply_player_action_result(socket.assigns, result, state) do
          {:done, updates} ->
            {:noreply, assign(socket, updates)}
        end

      {:error, reason} ->
        {:noreply, assign(socket, CampaignFlow.apply_player_action_error(reason))}
    end
  end

  @impl true
  def handle_info({:display_enemy_turns, [result | rest]}, socket) do
    campaign_id = socket.assigns.campaign_id
    state = Server.get_state(campaign_id)

    case CampaignFlow.apply_enemy_turn(socket.assigns, result, rest, state) do
      {:done, updates} ->
        {:noreply, assign(socket, updates)}

      {:continue, updates, next_rest} ->
        send(self(), {:display_enemy_turns, next_rest})
        {:noreply, assign(socket, updates)}
    end
  end

  @impl true
  def handle_info(:do_end_session, socket) do
    campaign_id = socket.assigns.campaign_id

    result = Server.end_session(campaign_id)

    {:noreply, assign(socket, CampaignFlow.apply_end_session_result(socket.assigns, result))}
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

      <.chat_feed
        messages={@messages}
        character={@character}
        ending_session={@ending_session}
        loading={@loading}
        error={@error}
        last_player_message={@last_player_message}
      />

      <.campaign_status_bars
        characters={@characters}
        character={@character}
        location={@current_location}
        phase={@phase}
        combat_state={@combat_state}
        mode={@mode}
      />

      <.chat_input input_text={@input_text} loading={@loading} processing={@processing} />
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────
end
