defmodule TrpgMasterWeb.CampaignLive do
  use TrpgMasterWeb, :live_view

  import TrpgMasterWeb.GameComponents

  alias TrpgMaster.AI.{Client, PromptBuilder, Tools}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:messages, [])
     |> assign(:conversation_history, [])
     |> assign(:input_text, "")
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    message = String.trim(message)

    if message == "" do
      {:noreply, socket}
    else
      # Add player message to display
      messages = socket.assigns.messages ++ [%{type: :player, text: message}]

      # Add to conversation history (Claude API format)
      conversation_history =
        socket.assigns.conversation_history ++ [%{role: "user", content: message}]

      socket =
        socket
        |> assign(:messages, messages)
        |> assign(:conversation_history, conversation_history)
        |> assign(:input_text, "")
        |> assign(:loading, true)
        |> assign(:error, nil)

      # Trigger async AI call
      send(self(), {:call_ai, conversation_history})

      {:noreply, socket}
    end
  end

  def handle_event("send_message", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:call_ai, conversation_history}, socket) do
    system_prompt = PromptBuilder.system_prompt()
    tools = Tools.definitions()

    case Client.chat(system_prompt, conversation_history, tools) do
      {:ok, result} ->
        # Add tool results to display
        messages =
          Enum.reduce(result.tool_results, socket.assigns.messages, fn tool_result, acc ->
            case tool_result do
              %{result: dice_result} -> acc ++ [%{type: :dice, result: dice_result}]
              _ -> acc
            end
          end)

        # Add DM response to display
        messages = messages ++ [%{type: :dm, text: result.text}]

        # Add assistant response to conversation history
        updated_history = conversation_history ++ [%{role: "assistant", content: result.text}]

        {:noreply,
         socket
         |> assign(:messages, messages)
         |> assign(:conversation_history, updated_history)
         |> assign(:loading, false)}

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
        <h1>AI TRPG Master</h1>
        <span class="mode-badge">모험 모드</span>
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
end
