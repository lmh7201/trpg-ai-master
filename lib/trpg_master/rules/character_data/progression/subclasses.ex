defmodule TrpgMaster.Rules.CharacterData.Progression.Subclasses do
  @moduledoc false

  alias TrpgMaster.Rules.CharacterData

  def subclasses_for_class(class_id) when is_binary(class_id) do
    CharacterData.subclasses()
    |> Enum.filter(fn subclass -> subclass["classId"] == class_id end)
  end

  def subclasses_for_class(_), do: []

  def resolve_subclass_name(class_id, subclass_name)
      when is_binary(subclass_name) and subclass_name != "" do
    name_lower = String.downcase(subclass_name)

    subclasses_for_class(class_id)
    |> Enum.find(fn subclass ->
      ko = get_in(subclass, ["name", "ko"]) || ""
      en = get_in(subclass, ["name", "en"]) || ""
      String.downcase(ko) == name_lower || String.downcase(en) == name_lower
    end)
    |> case do
      nil ->
        subclass_name

      subclass ->
        get_in(subclass, ["name", "ko"]) || get_in(subclass, ["name", "en"]) || subclass_name
    end
  end

  def resolve_subclass_name(_, name), do: name

  def resolve_subclass_id(class_id, subclass_name)
      when is_binary(subclass_name) and subclass_name != "" do
    name_lower = String.downcase(subclass_name)

    subclasses_for_class(class_id)
    |> Enum.find(fn subclass ->
      ko = get_in(subclass, ["name", "ko"]) || ""
      en = get_in(subclass, ["name", "en"]) || ""
      id = subclass["id"] || ""

      String.downcase(ko) == name_lower ||
        String.downcase(en) == name_lower ||
        String.downcase(id) == name_lower
    end)
    |> case do
      nil -> nil
      subclass -> subclass["id"]
    end
  end

  def resolve_subclass_id(_, _), do: nil
end
