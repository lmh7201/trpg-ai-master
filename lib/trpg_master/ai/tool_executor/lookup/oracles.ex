defmodule TrpgMaster.AI.ToolExecutor.Lookup.Oracles do
  @moduledoc false

  alias TrpgMaster.Oracle.Loader, as: OracleLoader

  def consult_oracle(input) do
    oracle_name = Map.get(input, "oracle_name", "")
    question = Map.get(input, "question")

    case OracleLoader.random_result(oracle_name) do
      {:ok, result} ->
        response = %{"oracle" => oracle_name, "result" => result}
        response = if question, do: Map.put(response, "question", question), else: response
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def list_oracles do
    oracles =
      OracleLoader.list()
      |> Enum.map(fn oracle ->
        meta = oracle["metadata"] || %{}

        %{
          "name" => meta["name"],
          "name_ko" => meta["name_ko"],
          "description" => meta["description"],
          "category" => meta["category"]
        }
      end)
      |> Enum.sort_by(& &1["name"])

    {:ok, %{"oracles" => oracles}}
  end
end
