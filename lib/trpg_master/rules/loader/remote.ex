defmodule TrpgMaster.Rules.Loader.Remote do
  @moduledoc false

  alias TrpgMaster.Rules.Loader.{Indexer, Manifest, Source}
  require Logger

  def load_data_file(table, spec, token, timeout, fallback_fun)
      when is_function(fallback_fun, 0) do
    url = "#{Manifest.github_raw_base()}/#{spec.filename}"

    case Source.fetch_json(url, token, timeout) do
      {:ok, raw} ->
        entries = Indexer.extract_list(raw, spec.list_key)
        count = Indexer.insert_entries(table, spec.type, spec.name_style, entries)
        Indexer.log_columns(spec.type, entries)
        Logger.info("Rules.Loader: [GitHub] #{spec.filename} → #{spec.type} #{count}개")

      {:error, reason} ->
        Logger.warning("Rules.Loader: [GitHub] #{spec.filename} fetch 실패 (#{reason}) → 로컬 파일로 대체")

        fallback_fun.()
    end
  end

  def load_rule_file(table, filename, token, timeout, fallback_fun)
      when is_function(fallback_fun, 0) do
    url = "#{Manifest.github_raw_base()}/#{filename}"

    case Source.fetch_json(url, token, timeout) do
      {:ok, raw} ->
        count = Indexer.insert_rule_document(table, raw)
        Logger.info("Rules.Loader: [GitHub] #{filename} → rule #{count}개")

      {:error, reason} ->
        Logger.warning("Rules.Loader: [GitHub] #{filename} fetch 실패 (#{reason}) → 로컬 파일로 대체")

        fallback_fun.()
    end
  end
end
