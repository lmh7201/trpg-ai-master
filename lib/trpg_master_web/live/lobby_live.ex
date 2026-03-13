defmodule TrpgMasterWeb.LobbyLive do
  use TrpgMasterWeb, :live_view

  alias TrpgMaster.Campaign.{Manager, Persistence}

  @impl true
  def mount(_params, _session, socket) do
    campaigns = Persistence.list_campaigns()

    {:ok,
     socket
     |> assign(:campaigns, campaigns)
     |> assign(:new_name, "")
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create_campaign", %{"name" => name}, socket) do
    name = String.trim(name)

    if name == "" do
      {:noreply, assign(socket, :error, "캠페인 이름을 입력하세요.")}
    else
      case Manager.create_campaign(name) do
        {:ok, id} ->
          {:noreply, push_navigate(socket, to: "/play/#{id}")}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "생성 실패: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("delete_campaign", %{"id" => id}, socket) do
    Manager.delete_campaign(id)
    campaigns = Persistence.list_campaigns()
    {:noreply, assign(socket, :campaigns, campaigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-container">
      <header class="lobby-header">
        <h1>AI TRPG Master</h1>
        <p class="lobby-subtitle">D&D 5e Solo Play</p>
      </header>

      <div class="lobby-content">
        <section class="new-campaign">
          <h2>새 캠페인 시작</h2>
          <form phx-submit="create_campaign" class="new-campaign-form">
            <input
              type="text"
              name="name"
              value={@new_name}
              placeholder="캠페인 이름을 입력하세요"
              autocomplete="off"
            />
            <button type="submit">시작</button>
          </form>
          <%= if @error do %>
            <p class="lobby-error"><%= @error %></p>
          <% end %>
        </section>

        <%= if @campaigns != [] do %>
          <section class="campaign-list">
            <h2>저장된 캠페인</h2>
            <div class="campaigns">
              <%= for campaign <- @campaigns do %>
                <div class="campaign-card">
                  <a href={"/play/#{campaign.id}"} class="campaign-link">
                    <span class="campaign-name"><%= campaign.name %></span>
                    <span class="campaign-date"><%= format_date(campaign.updated_at) %></span>
                  </a>
                  <button
                    class="campaign-delete"
                    phx-click="delete_campaign"
                    phx-value-id={campaign.id}
                    data-confirm="정말 삭제하시겠습니까?"
                  >
                    삭제
                  </button>
                </div>
              <% end %>
            </div>
          </section>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_date(nil), do: ""

  defp format_date(date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M")

      _ ->
        date_str
    end
  end
end
