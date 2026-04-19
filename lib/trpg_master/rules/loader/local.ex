defmodule TrpgMaster.Rules.Loader.Local do
  @moduledoc false

  alias TrpgMaster.Rules.Loader.{Indexer, Manifest, Source}
  require Logger

  def load_data_file(table, spec) do
    path = Path.join(Manifest.rules_dir(), spec.filename)

    if File.exists?(path) do
      started_at = System.monotonic_time(:millisecond)

      case Source.read_json_file(path) do
        {:ok, raw} ->
          entries = Indexer.extract_list(raw, spec.list_key)
          count = Indexer.insert_entries(table, spec.type, spec.name_style, entries)
          elapsed = System.monotonic_time(:millisecond) - started_at
          Indexer.log_columns(spec.type, entries)

          Logger.info(
            "Rules.Loader: [로컬] #{spec.filename} → #{spec.type} #{count}개 (#{elapsed}ms)"
          )

        {:error, {:decode, reason}} ->
          Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")

        {:error, {:read, reason}} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end

  def load_rule_file(table, filename) do
    path = Path.join(Manifest.rules_dir(), filename)

    if File.exists?(path) do
      case Source.read_json_file(path) do
        {:ok, raw} ->
          count = Indexer.insert_rule_document(table, raw)
          Logger.info("Rules.Loader: [로컬] #{filename} → rule #{count}개")

        {:error, {:decode, reason}} ->
          Logger.warning("Rules.Loader: #{path} JSON 파싱 실패 — #{inspect(reason)}")

        {:error, {:read, reason}} ->
          Logger.warning("Rules.Loader: #{path} 읽기 실패 — #{inspect(reason)}")
      end
    else
      Logger.info("Rules.Loader: #{path} 파일 없음. 건너뜁니다.")
    end
  end
end
