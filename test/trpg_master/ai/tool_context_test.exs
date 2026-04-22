defmodule TrpgMaster.AI.ToolContextTest do
  # Process dictionary 기반이므로 async:false가 안전하다.
  use ExUnit.Case, async: false

  alias TrpgMaster.AI.ToolContext

  setup do
    ToolContext.clear()
    :ok
  end

  describe "with_context/2" do
    test "nil context는 put 없이 fun만 실행한다" do
      result =
        ToolContext.with_context(nil, fn ->
          :ok
        end)

      assert result == :ok
      assert ToolContext.characters() == []
      assert ToolContext.journal_entries() == []
    end

    test "context를 심고 fun 실행 후 정리한다" do
      context = %{characters: [%{"name" => "A"}], journal_entries: [%{"text" => "e"}]}

      inside =
        ToolContext.with_context(context, fn ->
          {ToolContext.characters(), ToolContext.journal_entries()}
        end)

      assert inside == {[%{"name" => "A"}], [%{"text" => "e"}]}

      # 탈출 후에는 비어 있어야 한다
      assert ToolContext.characters() == []
      assert ToolContext.journal_entries() == []
    end

    test "fun이 예외를 던져도 컨텍스트를 정리한다" do
      context = %{characters: [%{"name" => "A"}]}

      assert_raise RuntimeError, fn ->
        ToolContext.with_context(context, fn ->
          raise "boom"
        end)
      end

      assert ToolContext.characters() == []
    end
  end

  describe "put/1" do
    test ":characters 키만 있으면 그것만 저장한다" do
      ToolContext.put(%{characters: [%{"name" => "A"}]})
      assert ToolContext.characters() == [%{"name" => "A"}]
      assert ToolContext.journal_entries() == []
    end

    test ":journal_entries 키만 있으면 그것만 저장한다" do
      ToolContext.put(%{journal_entries: [%{"text" => "e"}]})
      assert ToolContext.journal_entries() == [%{"text" => "e"}]
      assert ToolContext.characters() == []
    end

    test "빈 맵은 아무 것도 저장하지 않는다" do
      ToolContext.put(%{})
      assert ToolContext.characters() == []
      assert ToolContext.journal_entries() == []
    end
  end

  describe "clear/0" do
    test "저장된 값을 전부 제거한다" do
      ToolContext.put(%{characters: [%{"name" => "A"}], journal_entries: [%{"text" => "e"}]})
      ToolContext.clear()

      assert ToolContext.characters() == []
      assert ToolContext.journal_entries() == []
    end
  end

  describe "characters/0, journal_entries/0" do
    test "값이 없으면 []를 돌려준다" do
      assert ToolContext.characters() == []
      assert ToolContext.journal_entries() == []
    end
  end
end
