defmodule TrpgMasterWeb.Game.HeaderComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  import Phoenix.HTML, only: [raw: 1]

  alias TrpgMaster.AI.Models

  @doc false
  attr(:campaign_id, :string, required: true)
  attr(:campaign_name, :string, required: true)
  attr(:phase, :atom, default: :exploration)
  attr(:ai_model, :string, required: true)
  attr(:mode, :atom, default: :adventure)
  attr(:loading, :boolean, default: false)

  def campaign_header(assigns) do
    ~H"""
    <header class="game-header">
      <div class="header-left">
        <a href="/" class="back-link">←</a>
        <h1><%= @campaign_name %></h1>
      </div>
      <div class="header-right">
        <span class="mode-badge"><%= phase_label(@phase) %></span>
        <button phx-click="toggle_model_selector" class="dm-select-btn" title="DM 선택">
          <%= provider_icon(@ai_model) %>
        </button>
        <button
          phx-click="toggle_mode"
          class={"mode-toggle #{if @mode == :debug, do: "mode-debug", else: "mode-adventure"}"}
          title={if @mode == :adventure, do: "디버그 모드로 전환", else: "모험 모드로 전환"}
        >
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
    """
  end

  @doc false
  attr(:available_models, :list, required: true)
  attr(:ai_model, :string, required: true)

  def model_selector_modal(assigns) do
    ~H"""
    <div>
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
    </div>
    """
  end

  defp phase_label(:exploration), do: "탐험"
  defp phase_label(:combat), do: "전투"
  defp phase_label(:dialogue), do: "대화"
  defp phase_label(:rest), do: "휴식"
  defp phase_label(_), do: "모험"

  defp provider_icon(model_id) do
    svg =
      case Models.provider_for(model_id) do
        :anthropic ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Claude">
            <path d="M13.83 3.52h-3.62L5.08 20.48h3.46l1.07-3.04h4.78l1.07 3.04h3.46L13.83 3.52zm-3.33 11.25 1.57-4.47 1.57 4.47H10.5z" fill="#D97757"/>
          </svg>
          """

        :openai ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="GPT">
            <path d="M22.28 9.82a5.98 5.98 0 0 0-.52-4.91 6.05 6.05 0 0 0-6.51-2.9A6.07 6.07 0 0 0 4.98 4.18a5.98 5.98 0 0 0-3.99 2.9 6.05 6.05 0 0 0 .74 7.1 5.98 5.98 0 0 0 .51 4.91 6.05 6.05 0 0 0 6.51 2.9A5.98 5.98 0 0 0 13.26 24a6.06 6.06 0 0 0 5.77-4.21 5.99 5.99 0 0 0 4-2.9 6.06 6.06 0 0 0-.75-7.07zM13.26 22.5a4.48 4.48 0 0 1-2.88-1.04l.14-.08 4.78-2.76a.79.79 0 0 0 .4-.68V11.2l2.02 1.17a.07.07 0 0 1 .04.05v5.58a4.5 4.5 0 0 1-4.5 4.5zM3.6 18.37a4.47 4.47 0 0 1-.53-3.01l.14.08 4.78 2.76a.77.77 0 0 0 .78 0l5.84-3.37v2.33a.08.08 0 0 1-.03.06L9.74 19.95A4.5 4.5 0 0 1 3.6 18.37zM2.34 7.9a4.49 4.49 0 0 1 2.37-1.97v5.65a.77.77 0 0 0 .39.68l5.81 3.35-2.02 1.17a.08.08 0 0 1-.07 0L3.55 13.9A4.5 4.5 0 0 1 2.34 7.89zm16.6 3.86-5.84-3.37 2.02-1.17a.08.08 0 0 1 .07 0l4.83 2.79a4.49 4.49 0 0 1-.68 8.1V12.44a.79.79 0 0 0-.4-.68zm2.01-3.02-.14-.09-4.77-2.78a.78.78 0 0 0-.79 0L9.41 9.23V6.9a.07.07 0 0 1 .03-.06l4.83-2.79a4.5 4.5 0 0 1 6.68 4.66zM8.31 12.86 6.29 11.7a.08.08 0 0 1-.04-.06V6.07a4.5 4.5 0 0 1 7.38-3.45l-.14.08-4.78 2.76a.79.79 0 0 0-.4.68v6.72zm1.1-2.37 2.6-1.5 2.61 1.5v3L12 15l-2.6-1.5V10.5z" fill="#10A37F"/>
          </svg>
          """

        :gemini ->
          """
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-label="Gemini">
            <defs>
              <linearGradient id="gemini-grad" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#4285F4"/>
                <stop offset="100%" stop-color="#8B5CF6"/>
              </linearGradient>
            </defs>
            <path d="M12 24A14.3 14.3 0 0 1 0 12 14.3 14.3 0 0 1 12 0a14.3 14.3 0 0 1 12 12 14.3 14.3 0 0 1-12 12z" fill="url(#gemini-grad)"/>
            <path d="M12 22A12.3 12.3 0 0 0 2 12 12.3 12.3 0 0 0 12 2a12.3 12.3 0 0 0 10 10 12.3 12.3 0 0 0-10 10z" fill="white"/>
          </svg>
          """

        _ ->
          "<span style=\"font-size:1.1rem\">🤖</span>"
      end

    raw(svg)
  end
end
