defmodule TrpgMaster.Campaign.SummarizerRequestTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.{State, Summarizer.Request}

  test "session/1 builds a session summary request with recent combined history" do
    state = %State{
      name: "별무리 원정대",
      ai_model: "gpt-5.4",
      exploration_history:
        for(index <- 1..15, do: %{"role" => "user", "content" => "탐험 #{index}"}),
      combat_history:
        for(index <- 1..10, do: %{"role" => "assistant", "content" => "전투 #{index}"})
    }

    request = Request.session(state)

    assert request.system == "You are a D&D session scribe."
    assert request.model == "gpt-5.4-mini"
    assert request.max_tokens == 1024
    assert hd(request.messages)["role"] == "user"
    assert hd(request.messages)["content"] =~ "별무리 원정대"
    assert length(request.messages) == 21
    assert List.last(request.messages)["content"] == "전투 10"
  end

  test "context/1 returns :skip when there are no assistant messages" do
    state = %State{
      exploration_history: [
        %{"role" => "user", "content" => "문을 연다"},
        %{"role" => "user", "content" => "주변을 살핀다"}
      ]
    }

    assert Request.context(state) == :skip
  end

  test "combat_history/1 builds a request with the previous combat summary" do
    state = %State{
      ai_model: "claude-sonnet-4-6",
      combat_history_summary: "고블린 둘이 쓰러졌고 오우거만 남았다.",
      combat_history: [
        %{"role" => "assistant", "content" => "오우거가 몽둥이를 크게 휘둘렀다."}
      ],
      combat_state: %{
        "player_names" => [],
        "enemies" => [%{"name" => "오우거", "hp_current" => 19, "hp_max" => 30}]
      }
    }

    request = Request.combat_history(state)

    assert request.system == "You are a TRPG combat summarizer."
    assert request.model == "claude-haiku-4-5-20251001"
    assert request.max_tokens == 600
    assert [message] = request.messages
    assert message["content"] =~ "고블린 둘이 쓰러졌고 오우거만 남았다."
    assert message["content"] =~ "오우거가 몽둥이를 크게 휘둘렀다."
  end
end
