defmodule TrpgMasterWeb.Game.CharacterSheetComponents do
  @moduledoc false

  use TrpgMasterWeb, :html

  alias Phoenix.LiveView.JS
  alias TrpgMasterWeb.Game.CharacterSheetSections

  @doc false
  attr(:character, :map, required: true)

  def character_sheet_modal(assigns) do
    ~H"""
    <div id="character-modal" style="display:none">
      <div class="character-modal-overlay" phx-click={JS.hide(to: "#character-modal")}></div>
      <div class="character-modal">
        <div class="char-modal-header">
          <div class="char-modal-title">
            <span class="char-modal-name"><%= @character["name"] || "캐릭터" %></span>
            <span class="char-modal-subtitle">
              <%= modal_subtitle(@character) %>
            </span>
          </div>
          <button phx-click={JS.hide(to: "#character-modal")} class="modal-close-btn">✕</button>
        </div>

        <div class="char-modal-body">
          <CharacterSheetSections.basic_info_section character={@character} />
          <CharacterSheetSections.prose_section
            :if={present_text?(@character["appearance"])}
            title="외모"
            content={@character["appearance"]}
          />
          <CharacterSheetSections.prose_section
            :if={present_text?(@character["backstory"])}
            title="배경 스토리"
            content={@character["backstory"]}
          />
          <CharacterSheetSections.abilities_section character={@character} />
          <CharacterSheetSections.combat_section character={@character} />
          <CharacterSheetSections.spell_slots_section character={@character} />
          <CharacterSheetSections.known_spells_section character={@character} />
          <CharacterSheetSections.inventory_section character={@character} />
          <CharacterSheetSections.grouped_features_section
            title="클래스 피처"
            features={@character["class_features"] || []}
            badge_class="char-feature-badge"
          />
          <CharacterSheetSections.grouped_features_section
            title={"서브클래스 피처 (#{@character["subclass"]})"}
            features={@character["subclass_features"] || []}
            badge_class="char-feature-badge char-subclass-feature-badge"
          />
          <CharacterSheetSections.badge_list_section
            title="특기"
            items={feat_names(@character)}
            container_class="char-features-list"
            badge_class="char-feature-badge"
          />
          <CharacterSheetSections.badge_list_section
            title="상태이상"
            items={@character["conditions"] || []}
            container_class="char-conditions"
            badge_class="char-condition-badge"
          />
        </div>
      </div>
    </div>
    """
  end

  defp modal_subtitle(character) do
    class_name = character["class"] || ""
    subclass = if character["subclass"], do: " (#{character["subclass"]})", else: ""
    level = if character["level"], do: " · #{character["level"]}레벨", else: ""

    "#{class_name}#{subclass}#{level}"
  end

  defp present_text?(text), do: is_binary(text) and text != ""

  defp feat_names(character) do
    (character["feats"] || []) ++
      if(character["background_feat"], do: [character["background_feat"]], else: [])
  end
end
