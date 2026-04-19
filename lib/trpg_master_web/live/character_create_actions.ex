defmodule TrpgMasterWeb.CharacterCreateActions do
  @moduledoc false

  alias TrpgMasterWeb.{CharacterCreateFlow, CharacterCreateSession}

  def handle(event, params, assigns, opts \\ [])

  def handle("select_class", %{"id" => class_id}, _assigns, opts) do
    {:assign, session(opts).select_class(class_id)}
  end

  def handle("toggle_class_skill", %{"skill" => skill}, assigns, opts) do
    {:assign, flow(opts).toggle_class_skill(assigns, skill)}
  end

  def handle("select_race", %{"id" => race_id}, _assigns, opts) do
    {:assign, session(opts).select_race(race_id)}
  end

  def handle("select_background", %{"id" => background_id}, _assigns, opts) do
    {:assign, session(opts).select_background(background_id)}
  end

  def handle("set_bg_ability", %{"rank" => rank, "key" => key}, assigns, opts) do
    {:assign, flow(opts).set_bg_ability(assigns, rank, key)}
  end

  def handle("set_ability_method", %{"method" => method}, _assigns, opts) do
    {:assign, flow(opts).set_ability_method(method)}
  end

  def handle("assign_ability", %{"key" => key, "score" => score_str}, assigns, opts) do
    case flow(opts).assign_ability(assigns, key, score_str) do
      {:ok, updates} -> {:assign, updates}
      :ignore -> :ignore
    end
  end

  def handle("clear_ability", %{"key" => key}, assigns, opts) do
    {:assign, flow(opts).clear_ability(assigns, key)}
  end

  def handle("roll_abilities", _params, _assigns, opts) do
    {:assign, flow(opts).roll_abilities()}
  end

  def handle("set_class_equip", %{"choice" => choice}, _assigns, opts) do
    {:assign, flow(opts).set_class_equip(choice)}
  end

  def handle("set_bg_equip", %{"choice" => choice}, _assigns, opts) do
    {:assign, flow(opts).set_bg_equip(choice)}
  end

  def handle("toggle_cantrip", %{"id" => spell_id}, assigns, opts) do
    {:assign, flow(opts).toggle_cantrip(assigns, spell_id)}
  end

  def handle("toggle_spell", %{"id" => spell_id}, assigns, opts) do
    {:assign, flow(opts).toggle_spell(assigns, spell_id)}
  end

  def handle("set_name", params, _assigns, opts) do
    {:assign, flow(opts).set_name(field_value(params, "name"))}
  end

  def handle("set_alignment", params, _assigns, opts) do
    {:assign, flow(opts).set_alignment(field_value(params, "alignment"))}
  end

  def handle("set_appearance", %{"value" => value}, _assigns, opts) do
    {:assign, flow(opts).set_appearance(value)}
  end

  def handle("set_backstory", %{"value" => value}, _assigns, opts) do
    {:assign, flow(opts).set_backstory(value)}
  end

  def handle("show_detail", %{"type" => type, "id" => id}, _assigns, opts) do
    {:assign, flow(opts).show_detail(type, id)}
  end

  def handle("close_detail", _params, _assigns, opts) do
    {:assign, flow(opts).close_detail()}
  end

  def handle("next_step", _params, assigns, opts) do
    case flow(opts).next_step(assigns) do
      {:ok, updates} -> {:assign, updates}
      {:error, updates} -> {:assign, updates}
    end
  end

  def handle("prev_step", _params, assigns, opts) do
    {:assign, flow(opts).prev_step(assigns)}
  end

  def handle("finish", _params, assigns, opts) do
    case session(opts).finish(assigns) do
      {:ok, campaign_id} -> {:navigate, "/play/#{campaign_id}"}
      {:error, message} -> {:assign, %{error: message}}
    end
  end

  defp flow(opts), do: Keyword.get(opts, :flow, CharacterCreateFlow)
  defp session(opts), do: Keyword.get(opts, :session, CharacterCreateSession)

  defp field_value(params, key) do
    Map.get(params, key) || Map.get(params, "value") || ""
  end
end
