defmodule LestrarvinurPhoenixWeb.MinigameTestItems do
  @moduledoc """
  Builds random item lists for the minigame test pages (/pacman-test,
  /invaders-test). Default mode uses random reading words; pass ?mode=math
  in the URL to get random math problems instead, so both flavors of the
  interstitial games can be tried without grinding out 100 cards.
  """

  alias LestrarvinurPhoenix.{Constants, MathConstants}
  alias LestrarvinurPhoenixWeb.MathGameLive

  @doc """
  Returns `count` items of shape %{id, text, category}. `mode` is the raw
  "mode" query param ("math" for math problems, anything else for words);
  `prefix` namespaces the generated ids (e.g. "pw" -> "pw-0", "pw-1", ...).
  """
  def build("math", count, prefix) do
    1..count
    |> Enum.map(fn idx ->
      problem = MathConstants.generate_problem(Enum.random(1..16))

      %{
        id: "#{prefix}-#{idx - 1}",
        text: "#{problem.question} = #{problem.answer}",
        category: MathGameLive.level_to_category(problem.level)
      }
    end)
  end

  def build(_mode, count, prefix) do
    [:yellow, :blue, :red, :green, :purple, :orange]
    |> Enum.flat_map(fn cat ->
      Constants.words_by_category(cat) |> Enum.map(fn word -> {word, cat} end)
    end)
    |> Enum.reject(fn {word, _cat} -> Constants.phrase?(word) end)
    |> Enum.shuffle()
    |> Enum.take(count)
    |> Enum.with_index()
    |> Enum.map(fn {{word, cat}, idx} ->
      %{id: "#{prefix}-#{idx}", text: word, category: cat}
    end)
  end

  @doc """
  Bottom-prompt text for a test page, matching what the real games show.
  """
  def prompt("math", verb), do: "#{verb} öll dæmin!"
  def prompt(_mode, verb), do: "#{verb} öll orðin!"
end
