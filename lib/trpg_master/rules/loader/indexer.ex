defmodule TrpgMaster.Rules.Loader.Indexer do
  @moduledoc false

  require Logger

  def extract_list(data, nil) when is_list(data), do: data

  def extract_list(data, list_key) when is_map(data) and is_binary(list_key) do
    case Map.get(data, list_key) do
      entries when is_list(entries) -> entries
      _ -> []
    end
  end

  def extract_list(_, _), do: []

  def insert_entries(table, type, name_style, entries) do
    Enum.reduce(entries, 0, fn entry, count ->
      count + insert_entry(table, type, name_style, entry)
    end)
  end

  def insert_rule_document(table, %{"id" => doc_id, "sections" => sections} = doc)
      when is_binary(doc_id) and is_list(sections) do
    :ets.insert(table, {{:rule, normalize(doc_id)}, doc})
    count = 1

    title_count = insert_rule_title_keys(table, doc_id, doc)

    section_count =
      Enum.reduce(sections, 0, fn section, acc ->
        acc + insert_rule_section(table, section)
      end)

    count + title_count + section_count
  end

  def insert_rule_document(_table, _doc), do: 0

  def log_columns(_type, []), do: :ok

  def log_columns(type, [first | _]) when is_map(first) do
    keys = first |> Map.keys() |> Enum.sort() |> Enum.join(", ")
    Logger.info("Rules.Loader: #{type} 컬럼 — [#{keys}]")
  end

  def normalize(name) when is_binary(name), do: name |> String.downcase() |> String.trim()
  def normalize(name), do: inspect(name)

  defp insert_entry(table, type, name_style, entry) when is_map(entry) do
    {ko_name, en_name} = extract_names(entry, name_style)

    inserted =
      if is_binary(ko_name) && ko_name != "" do
        :ets.insert(table, {{type, normalize(ko_name)}, entry})
        1
      else
        0
      end

    if is_binary(en_name) && en_name != "" do
      :ets.insert(table, {{type, normalize(en_name)}, entry})
    end

    inserted
  end

  defp insert_entry(_table, _type, _name_style, _entry), do: 0

  defp extract_names(entry, :name_object) do
    case Map.get(entry, "name") do
      %{"ko" => ko, "en" => en} -> {ko, en}
      name when is_binary(name) -> {name, nil}
      _ -> {nil, nil}
    end
  end

  defp insert_rule_title_keys(table, doc_id, doc) do
    title = Map.get(doc, "title", %{})
    ko = Map.get(title, "ko")
    en = Map.get(title, "en")

    ko_count =
      if is_binary(ko) && ko != "" && normalize(ko) != normalize(doc_id) do
        :ets.insert(table, {{:rule, normalize(ko)}, doc})
        1
      else
        0
      end

    en_count =
      if is_binary(en) && en != "" && normalize(en) != normalize(doc_id) do
        :ets.insert(table, {{:rule, normalize(en)}, doc})
        1
      else
        0
      end

    ko_count + en_count
  end

  defp insert_rule_section(table, %{"id" => section_id} = section)
       when is_binary(section_id) do
    :ets.insert(table, {{:rule, normalize(section_id)}, section})

    title = Map.get(section, "title", %{})
    ko = Map.get(title, "ko")
    en = Map.get(title, "en")

    ko_count =
      if is_binary(ko) && ko != "" && normalize(ko) != normalize(section_id) do
        :ets.insert(table, {{:rule, normalize(ko)}, section})
        1
      else
        0
      end

    en_count =
      if is_binary(en) && en != "" && normalize(en) != normalize(section_id) do
        :ets.insert(table, {{:rule, normalize(en)}, section})
        1
      else
        0
      end

    sub_count =
      case Map.get(section, "content") do
        content when is_list(content) ->
          content
          |> Enum.filter(fn item -> is_map(item) && Map.get(item, "type") == "subsection" end)
          |> Enum.reduce(0, fn subsection, acc -> acc + insert_rule_section(table, subsection) end)

        _ ->
          0
      end

    1 + ko_count + en_count + sub_count
  end

  defp insert_rule_section(_table, _section), do: 0
end
