defmodule TrpgMasterWeb.HistoryLive do
  use TrpgMasterWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  alias TrpgMaster.Campaign.Persistence

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Persistence.load_campaign_history(campaign_id) do
      {:ok, %{name: name, sessions: sessions, summary_logs: summary_logs}} ->
        {:ok,
         socket
         |> assign(:campaign_id, campaign_id)
         |> assign(:campaign_name, name)
         |> assign(:sessions, sessions)
         |> assign(:summary_logs, summary_logs)
         |> assign(:view_mode, :campaign)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "캠페인을 찾을 수 없습니다.")
         |> push_navigate(to: "/")}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, "캠페인 기록을 불러오지 못했습니다.")
         |> push_navigate(to: "/")}
    end
  end

  # ── 모드 전환 ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("switch_view", %{"mode" => "campaign"}, socket) do
    {:noreply, assign(socket, :view_mode, :campaign)}
  end

  def handle_event("switch_view", %{"mode" => "ai_summary"}, socket) do
    {:noreply, assign(socket, :view_mode, :ai_summary)}
  end

  # ── Render ─────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <div class="history-container">
      <header class="history-header">
        <div class="header-left">
          <a href={"/play/#{@campaign_id}"} class="back-link">←</a>
          <div class="history-title-group">
            <h1><%= @campaign_name %></h1>
            <span class="history-subtitle">모험 기록</span>
          </div>
        </div>
      </header>

      <div class="history-tabs">
        <button
          class={"history-tab #{if @view_mode == :campaign, do: "history-tab-active"}"}
          phx-click="switch_view"
          phx-value-mode="campaign"
        >
          📋 캠페인 요약
        </button>
        <button
          class={"history-tab #{if @view_mode == :ai_summary, do: "history-tab-active"}"}
          phx-click="switch_view"
          phx-value-mode="ai_summary"
        >
          🤖 AI 요약
        </button>
      </div>

      <div class="history-scroll" id="history-scroll" phx-hook="ScrollBottom">
        <div class="novel-content">
          <%= if @view_mode == :campaign do %>
            <%= if @sessions == [] do %>
              <p class="novel-empty">
                아직 기록된 세션이 없습니다.<br/>
                <span style="font-size: 0.85rem;">세션을 종료(📋)하면 요약이 여기에 쌓입니다.</span>
              </p>
            <% end %>

            <%= for {session_md, idx} <- Enum.with_index(@sessions) do %>
              <div class="novel-session" id={"session-#{idx}"}>
                <%= raw(format_markdown(session_md)) %>
              </div>
            <% end %>
          <% else %>
            <%= if @summary_logs == [] do %>
              <p class="novel-empty">
                아직 AI 요약 로그가 없습니다.<br/>
                <span style="font-size: 0.85rem;">대화를 진행하면 매 턴마다 AI 요약이 기록됩니다.</span>
              </p>
            <% end %>

            <%= for {entry, idx} <- Enum.with_index(@summary_logs) do %>
              <div class="summary-entry" id={"summary-#{idx}"}>
                <div class="summary-timestamp"><%= format_timestamp(entry["timestamp"]) %></div>
                <div class="summary-text"><%= raw(format_markdown(entry["summary"])) %></div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp format_markdown(text) when is_binary(text) do
    case Earmark.as_html(text, %Earmark.Options{breaks: true}) do
      {:ok, html, _warnings} ->
        html

      {:error, _, _} ->
        text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp format_markdown(_), do: ""

  defp format_timestamp(nil), do: ""

  defp format_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} ->
        Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

      _ ->
        ts
    end
  end
end
