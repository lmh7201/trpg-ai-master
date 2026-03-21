defmodule TrpgMasterWeb.LobbyLive do
  use TrpgMasterWeb, :live_view

  alias TrpgMaster.Campaign.{Manager, Persistence}
  alias TrpgMaster.AI.Models

  @impl true
  def mount(_params, _session, socket) do
    campaigns = Persistence.list_campaigns()

    socket =
      socket
      |> assign(:campaigns, campaigns)
      |> assign(:new_name, "")
      |> assign(:selected_model, Models.default_model())
      |> assign(:available_models, Models.list_with_status())
      |> assign(:error, nil)

    socket =
      if connected?(socket) do
        push_event(socket, "campaigns_loaded", %{
          campaigns: campaigns,
          cached_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("create_campaign", %{"name" => name} = params, socket) do
    name = String.trim(name)
    model_id = Map.get(params, "model", Models.default_model())

    if name == "" do
      {:noreply, assign(socket, :error, "캠페인 이름을 입력하세요.")}
    else
      case Manager.create_campaign(name, model_id) do
        {:ok, id} ->
          {:noreply, push_navigate(socket, to: "/create/#{id}")}

        {:error, reason} ->
          {:noreply, assign(socket, :error, "생성 실패: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("delete_campaign", %{"id" => id}, socket) do
    Manager.delete_campaign(id)
    campaigns = Persistence.list_campaigns()

    {:noreply,
     socket
     |> assign(:campaigns, campaigns)
     |> push_event("campaigns_loaded", %{
         campaigns: campaigns,
         cached_at: DateTime.utc_now() |> DateTime.to_iso8601()
       })}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="lobby-container">
      <header class="lobby-header">
        <h1>AI TRPG Master</h1>
        <p class="lobby-subtitle">D&D 5.5e Solo Play</p>
      </header>

      <div class="lobby-content" id="lobby-content" phx-hook="CampaignCache">
        <section class="new-campaign">
          <h2>새 캠페인 시작</h2>
          <form phx-submit="create_campaign" class="new-campaign-form">
            <div class="new-campaign-form-row">
              <input
                type="text"
                name="name"
                value={@new_name}
                placeholder="캠페인 이름을 입력하세요"
                autocomplete="off"
              />
              <button type="submit">시작</button>
            </div>
            <div class="dm-select-group">
              <label class="dm-select-label">🤖 DM 선택</label>
              <select name="model" class="dm-model-select">
                <%= for provider <- [:anthropic, :openai, :gemini] do %>
                  <optgroup label={Models.provider_label(provider)}>
                    <%= for model <- Enum.filter(@available_models, &(&1.provider == provider)) do %>
                      <option
                        value={model.id}
                        selected={model.id == @selected_model}
                        disabled={not model.available}
                      >
                        <%= model.name %><%= unless model.available, do: " (API 키 미설정)", else: "" %>
                      </option>
                    <% end %>
                  </optgroup>
                <% end %>
              </select>
            </div>
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
