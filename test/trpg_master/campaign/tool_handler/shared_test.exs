defmodule TrpgMaster.Campaign.ToolHandler.SharedTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Campaign.ToolHandler.Shared

  describe "sanitize_name/1" do
    test "정상 문자열은 trim만 해서 돌려준다" do
      assert Shared.sanitize_name("  아리아  ") == "아리아"
      assert Shared.sanitize_name("아리아") == "아리아"
    end

    test "공백만 있는 문자열은 nil이 된다" do
      assert Shared.sanitize_name("   ") == nil
      assert Shared.sanitize_name("\t\n") == nil
      assert Shared.sanitize_name("") == nil
    end

    test "nil/비문자열 입력은 nil을 돌려준다" do
      assert Shared.sanitize_name(nil) == nil
      assert Shared.sanitize_name(123) == nil
      assert Shared.sanitize_name(%{}) == nil
      assert Shared.sanitize_name([]) == nil
    end
  end

  describe "maybe_put/3" do
    test "값이 nil이면 map을 그대로 돌려준다" do
      assert Shared.maybe_put(%{"a" => 1}, "b", nil) == %{"a" => 1}
    end

    test "값이 nil이 아니면 넣는다" do
      assert Shared.maybe_put(%{"a" => 1}, "b", 2) == %{"a" => 1, "b" => 2}
    end

    test "빈 문자열도 nil이 아니므로 넣는다 (nil 체크만 수행)" do
      assert Shared.maybe_put(%{}, "x", "") == %{"x" => ""}
    end

    test "false 값도 넣는다" do
      assert Shared.maybe_put(%{}, "x", false) == %{"x" => false}
    end

    test "atom 키도 사용 가능하다" do
      assert Shared.maybe_put(%{}, :x, 1) == %{x: 1}
    end
  end
end
