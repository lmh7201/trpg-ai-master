defmodule TrpgMaster.AI.ToolExecutor.State do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  def get_character_info(input) do
    category = Map.get(input, "category", "summary")
    characters = Process.get(:campaign_characters, [])

    case characters do
      [character | _] ->
        info = CharacterData.get_character_info(character, category)
        {:ok, %{"status" => "ok", "character" => info}}

      [] ->
        {:ok, %{"status" => "error", "message" => "등록된 캐릭터가 없습니다."}}
    end
  end

  def update_character(input) do
    {:ok, %{"status" => "ok", "message" => "#{input["character_name"]}의 상태가 업데이트되었습니다."}}
  end

  def register_npc(input) do
    {:ok, %{"status" => "ok", "message" => "NPC '#{input["name"]}'이(가) 등록/수정되었습니다."}}
  end

  def update_quest(input) do
    {:ok,
     %{
       "status" => "ok",
       "message" => "퀘스트 '#{input["quest_name"]}'이(가) 업데이트되었습니다."
     }}
  end

  def set_location(input) do
    {:ok, %{"status" => "ok", "message" => "현재 위치가 '#{input["location_name"]}'(으)로 변경되었습니다."}}
  end

  def start_combat(input) do
    participants = input["participants"] || []

    {:ok,
     %{
       "status" => "ok",
       "message" => "전투가 시작되었습니다. 참가자: #{Enum.join(participants, ", ")}"
     }}
  end

  def end_combat(_input) do
    {:ok,
     %{
       "status" => "ok",
       "message" => "전투가 종료되었습니다. XP가 지급되었으며 레벨업 조건이 충족되면 자동으로 처리됩니다."
     }}
  end

  def level_up(input) do
    asi_msg =
      case input["asi"] do
        nil ->
          ""

        asi when is_map(asi) ->
          parts = Enum.map(asi, fn {stat, amt} -> "#{stat} +#{amt}" end)
          " ASI 적용: #{Enum.join(parts, ", ")}."
      end

    feat_msg =
      case input["feat"] do
        nil -> ""
        "" -> ""
        feat_name when is_binary(feat_name) -> " 특기 습득: #{feat_name}."
      end

    spells_msg =
      case input["new_spells"] do
        nil ->
          ""

        [] ->
          ""

        spells when is_list(spells) ->
          names = Enum.map(spells, fn spell -> spell["name"] || "알 수 없음" end)
          " 새 주문 습득: #{Enum.join(names, ", ")}."
      end

    {features_msg, subclass_features_msg} =
      level_up_feature_messages(Process.get(:campaign_characters, []), input)

    {:ok,
     %{
       "status" => "ok",
       "message" =>
         "#{input["character_name"]} 레벨업이 처리되었습니다. HP, 숙련 보너스, 주문 슬롯, 클래스/서브클래스 피처가 자동으로 재계산됩니다.#{features_msg}#{subclass_features_msg}#{asi_msg}#{feat_msg}#{spells_msg}",
       "note" => "레벨업 서술 시 위의 새 클래스 피처와 서브클래스 피처를 플레이어에게 설명하세요."
     }}
  end

  def write_journal(_input) do
    {:ok, %{"status" => "ok", "message" => "저널에 기록되었습니다."}}
  end

  def read_journal(input) do
    category = Map.get(input, "category")
    entries = Process.get(:journal_entries, [])

    filtered =
      if category do
        Enum.filter(entries, &(&1["category"] == category))
      else
        entries
      end

    {:ok, %{"status" => "ok", "entries" => filtered, "total" => length(filtered)}}
  end

  defp level_up_feature_messages(characters, input) do
    case Enum.find(characters, fn character ->
           (character["name"] || "") |> String.downcase() ==
             (input["character_name"] || "") |> String.downcase()
         end) do
      nil ->
        {"", ""}

      character ->
        class_id = character["class_id"]
        current_level = character["level"] || 1
        new_level = current_level + 1

        new_features = CharacterData.class_features_for_level(class_id, new_level)

        class_feat_msg =
          if new_features != [] do
            " 새 클래스 피처: #{Enum.join(new_features, ", ")}."
          else
            ""
          end

        sub_feat_msg =
          case character["subclass_id"] do
            nil ->
              ""

            subclass_id ->
              new_sub_features = CharacterData.subclass_features_for_level(subclass_id, new_level)

              if new_sub_features != [] do
                " 새 서브클래스 피처 (#{character["subclass"]}): #{Enum.join(new_sub_features, ", ")}."
              else
                ""
              end
          end

        {class_feat_msg, sub_feat_msg}
    end
  end
end
