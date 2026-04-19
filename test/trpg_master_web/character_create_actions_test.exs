defmodule TrpgMasterWeb.CharacterCreateActionsTest do
  use ExUnit.Case, async: true

  alias TrpgMasterWeb.CharacterCreateActions

  defmodule AlignmentFlowStub do
    def set_alignment(value), do: %{alignment: value}
  end

  defmodule AssignAbilityFlowStub do
    def assign_ability(_assigns, _key, _score_str), do: :ignore
  end

  defmodule NextStepFlowStub do
    def next_step(_assigns), do: {:error, %{error: "아직 선택이 부족합니다."}}
  end

  defmodule FinishSessionStub do
    def finish(_assigns), do: {:ok, "campaign-9"}
  end

  defmodule FinishErrorSessionStub do
    def finish(_assigns), do: {:error, "캐릭터 생성이 완료되지 않았습니다."}
  end

  test "handle/4 reads alignment from direct input payloads" do
    assert {:assign, %{alignment: "혼돈 선"}} =
             CharacterCreateActions.handle(
               "set_alignment",
               %{"value" => "혼돈 선"},
               %{},
               flow: AlignmentFlowStub
             )
  end

  test "handle/4 reads alignment from form change payloads" do
    assert {:assign, %{alignment: "질서 선"}} =
             CharacterCreateActions.handle(
               "set_alignment",
               %{"alignment" => "질서 선"},
               %{},
               flow: AlignmentFlowStub
             )
  end

  test "handle/4 preserves ignore results from ability assignment" do
    assert :ignore =
             CharacterCreateActions.handle(
               "assign_ability",
               %{"key" => "str", "score" => "bad"},
               %{},
               flow: AssignAbilityFlowStub
             )
  end

  test "handle/4 flattens next_step errors into assign updates" do
    assert {:assign, %{error: "아직 선택이 부족합니다."}} =
             CharacterCreateActions.handle(
               "next_step",
               %{},
               %{},
               flow: NextStepFlowStub
             )
  end

  test "handle/4 turns successful finish results into navigation" do
    assert {:navigate, "/play/campaign-9"} =
             CharacterCreateActions.handle(
               "finish",
               %{},
               %{campaign_id: "campaign-9"},
               session: FinishSessionStub
             )
  end

  test "handle/4 turns finish errors into assign updates" do
    assert {:assign, %{error: "캐릭터 생성이 완료되지 않았습니다."}} =
             CharacterCreateActions.handle(
               "finish",
               %{},
               %{campaign_id: "campaign-9"},
               session: FinishErrorSessionStub
             )
  end
end
