defmodule TrpgMasterWeb.CampaignPresenter.ToolMessages do
  @moduledoc false

  @narrated_tools ~w(
    register_npc
    update_quest
    set_location
    start_combat
    end_combat
    update_character
    write_journal
  )

  def append(messages, mode, result) do
    Enum.reduce(result.tool_results, messages, fn tool_result, acc ->
      case tool_result do
        %{result: %{"formatted" => _} = dice_result} ->
          if mode == :adventure && Map.get(tool_result.input || %{}, "hidden") do
            acc
          else
            acc ++ [%{type: :dice, result: dice_result}]
          end

        %{tool: tool_name, input: input, result: %{"status" => "ok"}}
        when tool_name in @narrated_tools ->
          if mode == :debug do
            message = build_tool_narrative(tool_name, input)
            acc ++ [%{type: :tool_narration, tool_name: tool_name, message: message}]
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp build_tool_narrative("register_npc", input) do
    name = input["name"] || "?"
    parts = ["'#{name}'"]
    parts = if input["description"], do: parts ++ [input["description"]], else: parts
    parts = if input["disposition"], do: parts ++ ["태도: #{input["disposition"]}"], else: parts
    parts = if input["location"], do: parts ++ ["위치: #{input["location"]}"], else: parts
    Enum.join(parts, " / ")
  end

  defp build_tool_narrative("update_quest", input) do
    name = input["quest_name"] || "?"
    status = if input["status"], do: " [#{input["status"]}]", else: ""
    desc = if input["description"], do: ": #{input["description"]}", else: ""
    "'#{name}'#{status}#{desc}"
  end

  defp build_tool_narrative("set_location", input) do
    name = input["location_name"] || "?"
    desc = if input["description"], do: " — #{input["description"]}", else: ""
    "'#{name}'#{desc}"
  end

  defp build_tool_narrative("start_combat", input) do
    participants = input["participants"] || []
    enemies = input["enemies"] || []
    part_str = if participants != [], do: Enum.join(participants, ", "), else: "?"

    enemy_str =
      if enemies != [] do
        enemy_names =
          Enum.map(enemies, fn enemy ->
            count = enemy["count"] || 1
            if count > 1, do: "#{enemy["name"]} x#{count}", else: enemy["name"]
          end)

        " vs #{Enum.join(enemy_names, ", ")}"
      else
        ""
      end

    "#{part_str}#{enemy_str}"
  end

  defp build_tool_narrative("end_combat", input) do
    parts = []
    loot = input["loot"] || []
    parts = if loot != [], do: parts ++ ["전리품: #{Enum.join(loot, ", ")}"], else: parts
    parts = if input["xp"], do: parts ++ ["#{input["xp"]}XP"], else: parts
    parts = if input["summary"], do: parts ++ [input["summary"]], else: parts
    if parts == [], do: "전투가 종료되었습니다.", else: Enum.join(parts, " / ")
  end

  defp build_tool_narrative("update_character", input) do
    name = input["character_name"] || "?"
    changes = input["changes"] || %{}
    parts = []
    parts = if changes["hp_current"], do: parts ++ ["HP → #{changes["hp_current"]}"], else: parts
    parts = if changes["ac"], do: parts ++ ["AC #{changes["ac"]}"], else: parts
    add = changes["inventory_add"] || []
    parts = if add != [], do: parts ++ ["획득: #{Enum.join(add, ", ")}"], else: parts
    remove = changes["inventory_remove"] || []
    parts = if remove != [], do: parts ++ ["제거: #{Enum.join(remove, ", ")}"], else: parts
    cond_add = changes["conditions_add"] || []
    parts = if cond_add != [], do: parts ++ ["상태이상: #{Enum.join(cond_add, ", ")}"], else: parts
    cond_remove = changes["conditions_remove"] || []

    parts =
      if cond_remove != [], do: parts ++ ["상태이상 해제: #{Enum.join(cond_remove, ", ")}"], else: parts

    parts = if changes["level"], do: parts ++ ["레벨 #{changes["level"]}"], else: parts

    if parts == [] do
      "'#{name}' 상태 업데이트"
    else
      "'#{name}': #{Enum.join(parts, ", ")}"
    end
  end

  defp build_tool_narrative("write_journal", input) do
    category = input["category"] || "note"
    entry = input["entry"] || ""
    preview = String.slice(entry, 0, 120)
    suffix = if String.length(entry) > 120, do: "…", else: ""
    "[#{category}] #{preview}#{suffix}"
  end

  defp build_tool_narrative(_tool, _input), do: "완료"
end
