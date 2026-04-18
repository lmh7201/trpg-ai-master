defmodule TrpgMaster.AI.Providers.Anthropic.RequestTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Anthropic.Request

  test "build/4 applies ephemeral cache control to system and last tool" do
    tools = [
      %{"name" => "lookup_rule"},
      %{"name" => "lookup_spell"}
    ]

    body =
      Request.build("system prompt", [%{"role" => "user", "content" => "안내해줘"}], tools,
        max_tokens: 321
      )

    assert body.max_tokens == 321

    assert body.system == [
             %{type: "text", text: "system prompt", cache_control: %{type: "ephemeral"}}
           ]

    assert List.last(body.tools).cache_control == %{type: "ephemeral"}
    assert hd(body.messages) == %{"role" => "user", "content" => "안내해줘"}
  end
end
