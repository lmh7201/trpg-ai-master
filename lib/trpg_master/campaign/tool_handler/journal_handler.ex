defmodule TrpgMaster.Campaign.ToolHandler.JournalHandler do
  @moduledoc """
  저널 관련 도구(`write_journal`, `read_journal`) 결과를 state에 반영한다.

  `read_journal`은 state를 바꾸지 않으며 `Tools.execute`에서 프로세스 컨텍스트로
  직접 응답을 만든다. 여기서는 그냥 no-op이다.
  """

  alias TrpgMaster.Campaign.ToolHandler.Shared
  require Logger

  @max_journal_entries 100

  def write(state, input) when is_map(input) do
    case Shared.sanitize_name(input["entry"]) do
      nil ->
        Logger.warning("[Campaign #{state.id}] write_journal: 엔트리 내용이 비어 있어 무시합니다.")
        state

      entry_text ->
        category = input["category"] || "note"

        entry = %{
          "text" => entry_text,
          "category" => category,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        Logger.info("저널 기록 [#{state.id}] [#{category}]: #{String.slice(entry_text, 0, 50)}...")

        entries = (state.journal_entries ++ [entry]) |> Enum.take(-@max_journal_entries)
        %{state | journal_entries: entries}
    end
  end

  def read(state, _input), do: state
end
