defmodule TrpgMasterWeb.CampaignFlowTest do
  use ExUnit.Case, async: false

  alias TrpgMaster.Campaign.State
  alias TrpgMasterWeb.CampaignFlow

  test "submit_message/2 trims player input and prepares loading state" do
    assigns =
      base_assigns(%{
        messages: [%{type: :system, text: "시작"}],
        input_text: "기존 입력",
        error: "이전 오류"
      })

    assert {:ok, updates, "횃불을 든다"} =
             CampaignFlow.submit_message(assigns, "  횃불을 든다  ")

    assert updates.messages == [
             %{type: :system, text: "시작"},
             %{type: :player, text: "횃불을 든다"}
           ]

    assert updates.input_text == ""
    assert updates.loading
    assert updates.processing
    assert updates.error == nil
    assert updates.last_player_message == "횃불을 든다"
  end

  test "retry_last/1 returns ignore when no retry target exists" do
    assert CampaignFlow.retry_last(base_assigns()) == :ignore
  end

  test "retry_last/1 reuses the previous player message" do
    assigns = base_assigns(%{last_player_message: "문을 연다", error: "실패"})

    assert {:ok, %{loading: true, error: nil}, "문을 연다"} =
             CampaignFlow.retry_last(assigns)
  end

  test "select_model/2 updates selected model when API key is configured" do
    previous = Application.get_env(:trpg_master, :openai_api_key)
    on_exit(fn -> Application.put_env(:trpg_master, :openai_api_key, previous) end)
    Application.put_env(:trpg_master, :openai_api_key, "test-key")

    assigns = base_assigns(%{messages: [%{type: :dm, text: "무엇을 하시겠습니까?"}]})

    assert {:ok, updates} = CampaignFlow.select_model(assigns, "gpt-5.4")
    assert updates.ai_model == "gpt-5.4"
    assert updates.show_model_selector == false
    assert List.last(updates.messages) == %{type: :system, text: "🤖 DM이 GPT-5.4(으)로 변경되었습니다."}
  end

  test "select_model/2 shows a warning when API key is missing" do
    previous = Application.get_env(:trpg_master, :google_api_key)
    on_exit(fn -> Application.put_env(:trpg_master, :google_api_key, previous) end)
    Application.put_env(:trpg_master, :google_api_key, nil)

    assigns = base_assigns(%{messages: []})

    assert {:error, updates} = CampaignFlow.select_model(assigns, "gemini-2.5-flash")
    assert updates.show_model_selector == false

    assert updates.messages == [
             %{
               type: :system,
               text: "⚠️ GOOGLE_API_KEY 환경변수가 설정되지 않았습니다. 서버 관리자에게 문의하세요."
             }
           ]
  end

  test "apply_player_action_result/3 keeps combat running when enemy turns remain" do
    assigns = base_assigns(%{messages: [%{type: :player, text: "공격한다"}], mode: :debug})

    state =
      sample_state(%{
        phase: :combat,
        current_location: "폐허",
        combat_state: %{"player_names" => ["아리아"], "round" => 2}
      })

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
             CampaignFlow.apply_player_action_result(
               assigns,
               [player_result, enemy_result],
               state
             )

    assert updates.loading
    assert updates.phase == :combat
    assert updates.character == %{"name" => "아리아"}

    assert updates.messages == [
             %{type: :player, text: "공격한다"},
             %{
               type: :tool_narration,
               tool_name: "set_location",
               message: "'폐허 안뜰' — 무너진 석상 사이"
             },
             %{type: :dm, text: "아리아가 먼저 움직였다."}
           ]
  end

  test "apply_player_action_result/3 completes a single result and clears processing" do
    assigns = base_assigns(%{messages: [%{type: :player, text: "살핀다"}], mode: :adventure})
    state = sample_state(%{current_location: "고대 도서관"})
    result = %{text: "먼지 낀 서가가 보인다.", tool_results: []}

    assert {:done, updates} = CampaignFlow.apply_player_action_result(assigns, result, state)

    assert updates.loading == false
    assert updates.processing == false
    assert updates.current_location == "고대 도서관"

    assert updates.messages == [
             %{type: :player, text: "살핀다"},
             %{type: :dm, text: "먼지 낀 서가가 보인다."}
           ]
  end

  test "apply_enemy_turn/4 keeps processing active while additional turns remain" do
    assigns = base_assigns(%{messages: [%{type: :dm, text: "아리아가 먼저 움직였다."}]})

    state =
      sample_state(%{
        phase: :combat,
        combat_state: %{"player_names" => ["아리아"], "round" => 2}
      })

    result = %{text: "고블린 궁수가 화살을 쐈다.", tool_results: []}
    rest = [%{text: "오우거가 포효했다.", tool_results: []}]

    assert {:continue, updates, ^rest} =
             CampaignFlow.apply_enemy_turn(assigns, result, rest, state)

    assert updates.loading
    assert updates.processing
    assert List.last(updates.messages) == %{type: :dm, text: "고블린 궁수가 화살을 쐈다."}
  end

  test "apply_end_session_result/2 appends summary messages on success" do
    assigns = base_assigns(%{messages: [%{type: :player, text: "오늘은 여기까지"}]})

    updates = CampaignFlow.apply_end_session_result(assigns, {:ok, "용사는 승리의 노래를 남겼다."})

    assert updates.loading == false
    assert updates.ending_session == false

    assert updates.messages == [
             %{type: :player, text: "오늘은 여기까지"},
             %{type: :system, text: "📋 세션이 종료되었습니다. 대화 기록이 저장되었습니다."},
             %{type: :dm, text: "용사는 승리의 노래를 남겼다."}
           ]
  end

  test "apply_end_session_result/2 formats failures for the UI" do
    updates = CampaignFlow.apply_end_session_result(base_assigns(), {:error, :timeout})

    assert updates.loading == false
    assert updates.ending_session == false
    assert updates.error == "세션 종료 실패: AI 응답이 너무 오래 걸리고 있습니다. 다시 시도해주세요."
  end

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        messages: [],
        processing: false,
        input_text: "",
        error: nil,
        last_player_message: nil,
        show_model_selector: false,
        mode: :adventure
      },
      overrides
    )
  end

  defp sample_state(overrides) do
    struct(
      State,
      Map.merge(
        %{
          id: "campaign-1",
          name: "잿빛 폐허",
          current_location: "성문",
          phase: :exploration,
          mode: :adventure,
          characters: [%{"name" => "아리아"}]
        },
        overrides
      )
    )
  end
end
