defmodule TrpgMaster.Rules.LoaderTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Rules.Loader

  test "parse_cr/1 handles fractions, integers, and invalid values" do
    assert Loader.parse_cr("1/8") == 0.125
    assert Loader.parse_cr("1/4") == 0.25
    assert Loader.parse_cr("1/2") == 0.5
    assert Loader.parse_cr("3") == 3.0
    assert Loader.parse_cr("24") == 24.0
    assert Loader.parse_cr("unknown") == nil
    assert Loader.parse_cr(nil) == nil
  end
end
