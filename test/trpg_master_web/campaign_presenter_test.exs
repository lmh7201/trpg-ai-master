defmodule TrpgMasterWeb.CampaignPresenterTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Models
  alias TrpgMaster.Campaign.State
  alias TrpgMasterWeb.CampaignPresenter

  test "mount_assigns/2 builds display messages and default UI assigns" do
    state = %State{
      id: "campaign-1",
      name: "발더 산길",
      exploration_history: [
        %{"role" => "user", "content" => "출발한다."},
        %{"role" => "assistant", "content" => "안개 낀 길이 펼쳐진다."}
      ],
      combat_history: [
        %{"role" => "user", "synthetic" => true, "content" => "skip"},
        %{"role" => "assistant", "content" => "전투가 끝났다."}
      ],
      characters: [%{"name" => "아리아"}],
      mode: :adventure
    }

    assigns = CampaignPresenter.mount_assigns("campaign-1", state)

    assert assigns.campaign_id == "campaign-1"
    assert assigns.campaign_name == "발더 산길"
    assert assigns.ai_model == Models.default_model()

    assert assigns.messages == [
             %{type: :player, text: "출발한다."},
             %{type: :dm, text: "안개 낀 길이 펼쳐진다."},
             %{type: :dm, text: "전투가 끝났다."}
           ]

    assert assigns.character == %{"name" => "아리아"}
    assert assigns.characters == [%{"name" => "아리아"}]
    assert is_list(assigns.available_models)
  end

  test "state_assigns/1 filters non-player characters during combat" do
    state = %State{
      characters: [
        %{"name" => "아리아"},
        %{"name" => "보린"},
        %{"name" => "고블린"}
      ],
      combat_state: %{"player_names" => ["아리아", "보린"]},
      current_location: "폐허",
      phase: :combat,
      mode: :adventure
    }

    assigns = CampaignPresenter.state_assigns(state)

    assert assigns.character == %{"name" => "아리아"}
    assert assigns.characters == [%{"name" => "아리아"}, %{"name" => "보린"}]
    assert assigns.phase == :combat
    assert assigns.current_location == "폐허"
  end

  test "append_tool_messages/3 hides hidden dice results in adventure mode" do
    result = %{
      tool_results: [
        %{
          tool: "roll_dice",
          input: %{"hidden" => true},
          result: %{"formatted" => "1d20 = 18"}
        }
      ]
    }

    assert CampaignPresenter.append_tool_messages([], :adventure, result) == []
  end

  test "append_tool_messages/3 adds dice and debug narration when allowed" do
    result = %{
      tool_results: [
        %{
          tool: "roll_dice",
          input: %{},
          result: %{"formatted" => "1d20 = 18"}
        },
        %{
          tool: "set_location",
          input: %{"location_name" => "잊힌 탑", "description" => "비에 젖은 폐허"},
          result: %{"status" => "ok"}
        }
      ]
    }

    assert CampaignPresenter.append_tool_messages([], :debug, result) == [
             %{type: :dice, result: %{"formatted" => "1d20 = 18"}},
             %{
               type: :tool_narration,
               tool_name: "set_location",
               message: "'잊힌 탑' — 비에 젖은 폐허"
             }
           ]
  end
end
