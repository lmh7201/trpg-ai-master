defmodule TrpgMaster.AI.Providers.HttpTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.AI.Providers.Http

  test "ssl_options/0 returns ssl verification options" do
    opts = Http.ssl_options()

    assert is_list(opts)
    assert Keyword.has_key?(opts, :verify)
  end

  test "post_json/4 returns connection failure for unreachable host" do
    assert {:error, reason} =
             Http.post_json(
               "https://127.0.0.1:1/unreachable",
               [{~c"content-type", ~c"application/json"}],
               %{"ping" => true},
               provider: "TestProvider",
               timeout: 100
             )

    assert reason in [:connection_failed, :timeout]
  end
end
