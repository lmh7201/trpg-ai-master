defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.Campaign.{Manager, Server}

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    # Ensure the campaign server is running
    case Manager.start_campaign(campaign_id) do
      {:ok, _id} ->
        state = Server.get_state(campaign_id)

        # Build display messages from conversation history
        messages = build_display_messages(state.conversation_history)

        {:ok,
         socket
         |> assign(:campaign_id, campaign_id)
         |> assign(:campaign_name, state.name)
         |> assign(:messages, messages)
         |> assign(:input_text, "")
         |> assign(:loading, false)
         |> assign(:error, nil)
         |> assign(:current_location, state.current_location)
         |> assign(:phase, state.phase)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "캠페인을 찾을 수 없습니다.")
         |> push_navigate(to: "/")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      # Add player message to display immediately
      messages = socket.assigns.messages ++ [%{type: :player, text: message}]

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:input_text, "")
        |> assign(:loading, true)
        |> assign(:error, nil)

      # Trigger async AI call via GenServer
      send(self(), {:call_ai, message})

      {:noreply, socket}
    end
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:call_ai, message}, socket) do
    campaign_id = socket.assigns.campaign_id

    case Server.player_action(campaign_id, message) do
      {:ok, result} ->
        # Add tool results to display
        messages =
          Enum.reduce(result.tool_results, socket.assigns.messages, fn tool_result, acc ->
            case tool_result do
              %{result: %{"formatted" => _} = dice_result} ->
                acc ++ [%{type: :dice, result: dice_result}]

              _ ->
                acc
            end
          end)

        # Add DM response to display
        messages = messages ++ [%{type: :dm, text: result.text}]

        # Get updated state for sidebar info
        state = Server.get_state(campaign_id)

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:loading, false)
         |> assign(:current_location, state.current_location)
         |> assign(:phase, state.phase)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:loading, false)
         |> assign(:error, "AI 오류: #{inspect(reason)}")}
    end
  end

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
              <.player_message text={msg.text} />
            <% :dice -> %>
              <.dice_result result={msg.result} />
            <% :system -> %>
              <.system_message text={msg.text} />
          <% end %>
        <% end %>

        <%= if @loading do %>
          <.typing_indicator />
        <% end %>

        <%= if @error do %>
          <div class="message error-message">
            <span><%= @error %></span>
          </div>
        <% end %>
      </div>

      <form class="input-area" phx-submit="send_message">
        <input
          type="text"
          name="message"
          value={@input_text}
          placeholder="무엇을 하시겠습니까?"
          autocomplete="off"
          disabled={@loading}
        />
        <button type="submit" disabled={@loading}>
          <span>전송</span>
        </button>
      </form>
    </div>
    """
  end

  # ── Private helpers ─────────────────────────────────────────────────────────

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
