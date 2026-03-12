defmodule TrpgMaster.Dice.RollerTest do
  use ExUnit.Case, async: true

  alias TrpgMaster.Dice.Roller

  describe "roll/2" do
    test "parses and rolls basic notation" do
      assert {:ok, result} = Roller.roll("2d6+3")
      assert result.notation == "2d6+3"
      assert length(result.rolls) == 2
      assert result.modifier == 3
      assert result.total == Enum.sum(result.rolls) + 3
    end

    test "handles notation without modifier" do
      assert {:ok, result} = Roller.roll("1d20")
      assert result.modifier == 0
      assert result.total == hd(result.rolls)
    end

    test "handles negative modifier" do
      assert {:ok, result} = Roller.roll("1d8-1")
      assert result.modifier == -1
    end

    test "supports advantage" do
      assert {:ok, result} = Roller.roll("1d20+5", advantage: true)
      assert length(result.rolls) == 2
      assert result.advantage == true
      assert result.total == Enum.max(result.rolls) + 5
    end

    test "supports disadvantage" do
      assert {:ok, result} = Roller.roll("1d20+5", disadvantage: true)
      assert length(result.rolls) == 2
      assert result.disadvantage == true
      assert result.total == Enum.min(result.rolls) + 5
    end

    test "includes label when provided" do
      assert {:ok, result} = Roller.roll("1d20", label: "공격 굴림")
      assert result.label == "공격 굴림"
    end

    test "returns error for invalid notation" do
      assert {:error, _} = Roller.roll("invalid")
    end
  end

  describe "format_result/1" do
    test "formats basic result" do
      result = %{
        notation: "1d20+5",
        rolls: [15],
        modifier: 5,
        total: 20,
        label: nil,
        advantage: false,
        disadvantage: false,
        natural_20: false,
        natural_1: false
      }

      formatted = Roller.format_result(result)
      assert formatted =~ "1d20+5"
      assert formatted =~ "15"
      assert formatted =~ "20"
    end
  end
end
