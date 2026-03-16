defmodule TrpgMasterWeb.HistoryLive do
  use TrpgMasterWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  alias TrpgMaster.Campaign.Persistence

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case load_campaign_data(campaign_id) do
      {:ok, name, sessions} ->
        {:ok,
         socket
         |> assign(:campaign_id, campaign_id)
         |> assign(:campaign_name, name)
         |> assign(:sessions, sessions)}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, "캠페인을 찾을 수 없습니다.")
         |> push_navigate(to: "/")}
    end
  end

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

      <div class="history-scroll">
        <div class="novel-content">
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
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp load_campaign_data(campaign_id) do
    summary_path =
      Path.join([
        Application.get_env(:trpg_master, :data_dir, "data"),
        "campaigns",
        sanitize(campaign_id),
        "campaign-summary.json"
      ])

    case File.read(summary_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, summary} ->
            {:ok, sessions} = Persistence.load_session_log(campaign_id)
            {:ok, summary["name"] || campaign_id, sessions}

          _ ->
            {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp sanitize(name) do
    name |> String.replace(~r/[\/\\:*?"<>|]/, "_") |> String.trim()
  end

  defp format_markdown(text) when is_binary(text) do
    case Earmark.as_html(text, %Earmark.Options{breaks: true}) do
      {:ok, html, _warnings} -> html
      {:error, _, _} ->
        text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp format_markdown(_), do: ""
end
