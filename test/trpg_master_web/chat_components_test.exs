defmodule TrpgMasterWeb.ChatComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TrpgMasterWeb.ChatComponents

  @endpoint TrpgMasterWeb.Endpoint

  test "chat_feed/1 renders all message types and runtime notices" do
    html =
      render_component(&ChatComponents.chat_feed/1,
        messages: [
          %{type: :dm, text: "**짙은 안개**가 몰려온다."},
          %{type: :player, text: "앞으로 나아간다."},
          %{type: :dice, result: %{"formatted" => "1d20 = 20", "natural_20" => true}},
          %{
            type: :tool_narration,
            tool_name: "set_location",
            message: "'폐허 안뜰' — 무너진 석상 사이"
          },
          %{type: :system, text: "자동 저장 완료"}
        ],
        character: %{"name" => "아리아"},
        ending_session: false,
        loading: true,
        error: "응답이 지연되고 있습니다.",
        last_player_message: "앞으로 나아간다."
      )

    assert html =~ "<strong>짙은 안개</strong>"
    assert html =~ "아리아"
    assert html =~ "앞으로 나아간다."
    assert html =~ "1d20 = 20"
    assert html =~ "크리티컬!"
    assert html =~ "폐허 안뜰"
    assert html =~ "자동 저장 완료"
    assert html =~ "응답이 지연되고 있습니다."
    assert html =~ "다시 시도"
    assert html =~ "typing-dots"
  end

  test "chat_feed/1 shows welcome message and ending-session notice" do
    html =
      render_component(&ChatComponents.chat_feed/1,
        messages: [],
        character: nil,
        ending_session: true,
        loading: true,
        error: nil,
        last_player_message: nil
      )

    assert html =~ "AI 던전 마스터에 오신 것을 환영합니다!"
    assert html =~ "세션 요약을 생성 중입니다..."
    refute html =~ "typing-dots"
  end

  test "chat_input/1 reflects processing state and disables submit while loading" do
    html =
      render_component(&ChatComponents.chat_input/1,
        input_text: "문을 조사한다",
        loading: true,
        processing: true
      )

    assert html =~ "DM이 응답을 준비하는 중..."
    assert html =~ "문을 조사한다"
    assert html =~ ~s(id="message-form")
    assert html =~ ~s(aria-label="전송")
    assert html =~ "disabled"
  end
end
