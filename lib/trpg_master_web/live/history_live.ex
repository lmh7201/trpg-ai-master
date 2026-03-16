defmodule TrpgMasterWeb.HistoryLive do
  use TrpgMasterWeb, :live_view

  import Phoenix.HTML, only: [raw: 1]

  alias TrpgMaster.Campaign.Persistence

  @impl true
  def mount(%{"id" => campaign_id}, _session, socket) do
    case Persistence.load(campaign_id) do
      {:ok, state} ->
        entries = build_novel_entries(state.conversation_history, state.characters)

        {:ok,
         socket
         |> assign(:campaign_id, campaign_id)
         |> assign(:campaign_name, state.name)
         |> assign(:entries, entries)
         |> assign(:character_name, extract_character_name(state.characters))}

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
          <%= if @entries == [] do %>
            <p class="novel-empty">아직 기록된 대화가 없습니다.</p>
          <% end %>

          <%= for {entry, idx} <- Enum.with_index(@entries) do %>
            <%= case entry.type do %>
              <% :dm -> %>
                <div class="novel-dm" id={"entry-#{idx}"}>
                  <%= raw(format_markdown(entry.text)) %>
                </div>
              <% :player -> %>
                <div class="novel-player" id={"entry-#{idx}"}>
                  <span class="novel-player-name"><%= @character_name %></span>
                  <span class="novel-player-text"><%= entry.text %></span>
                </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # ── Private helpers ──────────────────────────────────────────────────────────

  defp build_novel_entries(conversation_history, _characters) do
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

  defp extract_character_name([%{"name" => name} | _]) when is_binary(name), do: name
  defp extract_character_name(_), do: "플레이어"

  defp format_markdown(text) when is_binary(text) do
    case Earmark.as_html(text, %Earmark.Options{breaks: true}) do
      {:ok, html, _warnings} -> html
      {:error, _, _} ->
        text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp format_markdown(_), do: ""
end
