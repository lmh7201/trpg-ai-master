defmodule TrpgMasterWeb.CampaignSessionTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Campaign.State
  alias TrpgMasterWeb.CampaignSession

  test "mount_assigns/2 builds presenter assigns from the loaded state" do
    state = %State{
      id: "campaign-1",
      name: "은빛 탑",
      exploration_history: [%{"role" => "assistant", "content" => "안개가 내려앉는다."}],
      characters: [%{"name" => "아리아"}],
      mode: :adventure
    }

    assert {:ok, assigns} =
             CampaignSession.mount_assigns("campaign-1",
               start_campaign: fn "campaign-1" -> {:ok, self()} end,
               get_state: fn "campaign-1" -> state end
             )

    assert assigns.campaign_id == "campaign-1"
    assert assigns.campaign_name == "은빛 탑"
    assert assigns.character == %{"name" => "아리아"}
    assert List.last(assigns.messages) == %{type: :dm, text: "안개가 내려앉는다."}
  end

  test "mount_assigns/2 returns not_found when the campaign cannot be started" do
    assert {:error, :not_found} =
             CampaignSession.mount_assigns("missing-campaign",
               start_campaign: fn "missing-campaign" -> {:error, :not_found} end
             )
  end

  test "call_ai/3 returns enemy turns when combat results continue" do
    assigns = %{
      campaign_id: "campaign-2",
      messages: [%{type: :player, text: "공격한다"}],
      mode: :debug
    }

    state = %State{
      id: "campaign-2",
      current_location: "폐허",
      phase: :combat,
      mode: :debug,
      characters: [%{"name" => "아리아"}],
      combat_state: %{"player_names" => ["아리아"], "round" => 2}
    }

    player_result = %{
      text: "아리아가 먼저 움직였다.",
      tool_results: [
        %{
          tool: "set_location",
          input: %{"location_name" => "폐허 안뜰", "description" => "무너진 석상 사이"},
          result: %{"status" => "ok"}
        }
      ]
    }

    enemy_result = %{text: "고블린이 반격했다.", tool_results: []}

    assert {:enemy_turns, updates, [^enemy_result]} =
             CampaignSession.call_ai(assigns, "공격한다",
               player_action: fn "campaign-2", "공격한다" ->
                 {:ok, [player_result, enemy_result]}
               end,
               get_state: fn "campaign-2" -> state end
             )

    assert updates.phase == :combat
    assert updates.loading == true
    assert List.last(updates.messages) == %{type: :dm, text: "아리아가 먼저 움직였다."}
  end

  test "end_session/2 applies the formatted session summary result" do
    assigns = %{campaign_id: "campaign-3", messages: [%{type: :player, text: "오늘은 여기까지"}]}

    updates =
      CampaignSession.end_session(assigns,
        end_session: fn "campaign-3" -> {:ok, "용사는 승리의 노래를 남겼다."} end
      )

    assert updates.loading == false
    assert updates.ending_session == false
    assert List.last(updates.messages) == %{type: :dm, text: "용사는 승리의 노래를 남겼다."}
  end
end
