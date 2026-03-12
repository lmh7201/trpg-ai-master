defmodule TrpgMaster.Dice.Roller do
  @moduledoc """
  순수 Elixir 주사위 굴림.
  "2d6+3", "1d20", "4d8-1" 등의 표기법 파싱 및 실행.
  어드밴티지/디스어드밴티지 지원.
  """

  @doc """
  주사위 표기법을 파싱하고 굴린다.

  ## Options
    - `:label` - 주사위 굴림 설명 (예: "공격 굴림")
    - `:advantage` - true면 d20을 2번 굴려 높은 값 선택
    - `:disadvantage` - true면 d20을 2번 굴려 낮은 값 선택

  ## Examples
      iex> TrpgMaster.Dice.Roller.roll("2d6+3")
      %{notation: "2d6+3", rolls: [3, 5], modifier: 3, total: 11, label: nil, ...}
  """
  def roll(notation, opts \\ []) do
    label = Keyword.get(opts, :label)
    advantage = Keyword.get(opts, :advantage, false)
    disadvantage = Keyword.get(opts, :disadvantage, false)

    case parse(notation) do
      {:ok, count, sides, modifier} ->
        {rolls, final_rolls} =
          if (advantage || disadvantage) && sides == 20 && count == 1 do
            roll1 = roll_die(sides)
            roll2 = roll_die(sides)
            chosen = if advantage, do: max(roll1, roll2), else: min(roll1, roll2)
            {[roll1, roll2], [chosen]}
          else
            dice = for _ <- 1..count, do: roll_die(sides)
            {dice, dice}
          end

        total = Enum.sum(final_rolls) + modifier

        {:ok,
         %{
           notation: notation,
           rolls: rolls,
           modifier: modifier,
           total: total,
           label: label,
           advantage: advantage,
           disadvantage: disadvantage,
           natural_20: sides == 20 && count == 1 && hd(final_rolls) == 20,
           natural_1: sides == 20 && count == 1 && hd(final_rolls) == 1
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse(notation) do
    notation = String.trim(notation) |> String.downcase()

    case Regex.run(~r/^(\d+)d(\d+)([+-]\d+)?$/, notation) do
      [_, count_str, sides_str] ->
        {:ok, String.to_integer(count_str), String.to_integer(sides_str), 0}

      [_, count_str, sides_str, mod_str] ->
        {:ok, String.to_integer(count_str), String.to_integer(sides_str),
         String.to_integer(mod_str)}

      nil ->
        {:error, "잘못된 주사위 표기법: #{notation}"}
    end
  end

  defp roll_die(sides) do
    :rand.uniform(sides)
  end

  @doc """
  주사위 결과를 사람이 읽기 좋은 문자열로 변환한다.
  """
  def format_result(%{} = result) do
    rolls_str = Enum.map_join(result.rolls, ", ", &to_string/1)

    adv_str =
      cond do
        result.advantage -> " (어드밴티지)"
        result.disadvantage -> " (디스어드밴티지)"
        true -> ""
      end

    label_str = if result.label, do: "#{result.label}: ", else: ""
    mod_str = format_modifier(result.modifier)

    "#{label_str}#{result.notation}#{adv_str} = [#{rolls_str}]#{mod_str} = #{result.total}"
  end

  defp format_modifier(0), do: ""
  defp format_modifier(n) when n > 0, do: "+#{n}"
  defp format_modifier(n), do: "#{n}"
end
