defmodule LestrarvinurPhoenix.MathConstants do
  @moduledoc """
  Math flash card game constants: 12 difficulty levels, problem generators,
  weighted distribution, trophies, and encouragement messages.
  """

  @problems_to_unlock 200

  @prestige_threshold 2_000

  @levels [
    %{id: 1, name: "Samlagning upp að 10", color: "#fbbf24", op: :add, grade: 1},
    %{id: 2, name: "Frádráttur frá 10", color: "#34d399", op: :sub, grade: 1},
    %{id: 3, name: "Samlagning upp að 20", color: "#60a5fa", op: :add, grade: 1},
    %{id: 4, name: "Frádráttur frá 20", color: "#f472b6", op: :sub, grade: 1},
    %{id: 5, name: "Tugir: samlagning", color: "#fb923c", op: :add, grade: 2},
    %{id: 6, name: "Tugir: frádráttur", color: "#a78bfa", op: :sub, grade: 2},
    %{id: 7, name: "Samlagning upp að 100", color: "#2dd4bf", op: :add, grade: 2},
    %{id: 8, name: "Frádráttur innan 100", color: "#f87171", op: :sub, grade: 2},
    %{id: 9, name: "Samlagning með yfirfærslu", color: "#818cf8", op: :add, grade: 2},
    %{id: 10, name: "Frádráttur með lántöku", color: "#e879f9", op: :sub, grade: 2},
    %{id: 11, name: "Margföldun: ×2, ×5, ×10", color: "#fcd34d", op: :mul, grade: 3},
    %{id: 12, name: "Margföldun: ×3–×9", color: "#fb7185", op: :mul, grade: 3}
  ]

  # Trophies — same structure as reading trophies, with "mt_" prefix
  @trophies [
    %{id: "mt_50", threshold: 100, name: "Byrjandi", color: "#fbbf24"},
    %{id: "mt_100", threshold: 200, name: "Reiknisnillingur", color: "#34d399"},
    %{id: "mt_200", threshold: 400, name: "Tölustjarna", color: "#60a5fa"},
    %{id: "mt_300", threshold: 600, name: "Meistari", color: "#818cf8"},
    %{id: "mt_400", threshold: 800, name: "Stærðfræðihetja", color: "#a78bfa"},
    %{id: "mt_500", threshold: 1000, name: "Ofurhetja", color: "#f472b6"},
    %{id: "mt_750", threshold: 1500, name: "Galdramaður", color: "#fb7185"},
    %{id: "mt_1000", threshold: 2000, name: "Goðsögn", color: "#fcd34d"}
  ]

  @encouragements [
    "Vel gert!",
    "Frábært!",
    "Haltu áfram svona!",
    "Meistaralegt!",
    "Þetta gengur vel!",
    "Þú ert snillingur!",
    "Geggjað!",
    "Ekkert stoppar þig!",
    "Þú ert stjarna!",
    "Æðislegt!",
    "Flott hjá þér!",
    "Þú ert frábær!",
    "Mjög flott!",
    "Topp frammistaða!",
    "Þú getur þetta!",
    "Þú ert að verða betri!",
    "Alveg stórmerkilegt!",
    "Þetta er rosalega vel gert!",
    "Þú ert að læra svo mikið!",
    "Þú ert töff!",
    "Þú ert hetja!"
  ]

  def levels, do: @levels
  def trophies, do: @trophies
  def encouragements, do: @encouragements
  def problems_to_unlock, do: @problems_to_unlock
  def prestige_threshold, do: @prestige_threshold

  @doc """
  Get a random encouragement message.
  """
  def random_encouragement do
    Enum.random(@encouragements)
  end

  @doc """
  Get level definition by ID (1-12).
  """
  def get_level(id) do
    Enum.find(@levels, fn l -> l.id == id end)
  end

  @doc """
  Compute highest unlocked level based on per-level counts.
  Level N+1 unlocks when level N has >= 200 cards shown.
  """
  def highest_unlocked_level(level_counts) do
    Enum.reduce_while(1..12, 1, fn level, acc ->
      count = Map.get(level_counts, level, 0)

      if count >= @problems_to_unlock and level < 12 do
        {:cont, level + 1}
      else
        {:halt, acc}
      end
    end)
  end

  @doc """
  Compute weighted level distribution as a list of {level_id, weight} tuples.

  Uses a normal distribution centered near the highest unlocked level,
  with older levels getting progressively less weight but never zero.
  """
  def weighted_distribution(highest_level) when highest_level >= 1 do
    if highest_level == 1 do
      [{1, 1.0}]
    else
      # Center the distribution at highest - 0.5 (biased toward newest)
      center = highest_level - 0.5
      # Sigma scales with number of levels — wider spread as more unlock
      sigma = max(1.0, highest_level / 3.0)

      weights =
        for level <- 1..highest_level do
          # Gaussian weight
          w = :math.exp(-0.5 * :math.pow((level - center) / sigma, 2))
          {level, w}
        end

      # Normalize
      total = Enum.reduce(weights, 0.0, fn {_l, w}, acc -> acc + w end)
      Enum.map(weights, fn {l, w} -> {l, w / total} end)
    end
  end

  @doc """
  Pick a random level based on weighted distribution.
  """
  def pick_level(highest_level) do
    distribution = weighted_distribution(highest_level)
    roll = :rand.uniform()

    {picked, _} =
      Enum.reduce_while(distribution, {1, 0.0}, fn {level, weight}, {_current, cumulative} ->
        new_cumulative = cumulative + weight

        if roll <= new_cumulative do
          {:halt, {level, new_cumulative}}
        else
          {:cont, {level, new_cumulative}}
        end
      end)

    picked
  end

  @doc """
  Generate a single math problem for the given level.
  Returns %{question: "3 + 4", answer: 7, level: 1, a: 3, b: 4, op: :add}
  """
  def generate_problem(1) do
    a = Enum.random(0..10)
    b = Enum.random(0..(10 - a))
    build_problem(:add, a, b, 1)
  end

  def generate_problem(2) do
    a = Enum.random(1..10)
    b = Enum.random(0..a)
    build_problem(:sub, a, b, 2)
  end

  def generate_problem(3) do
    # Sum up to 20, at least one number > 5
    a = Enum.random(6..14)
    b = Enum.random(1..min(20 - a, 14))
    build_problem(:add, a, b, 3)
  end

  def generate_problem(4) do
    # Subtract from numbers up to 20, result >= 0
    a = Enum.random(11..20)
    b = Enum.random(1..a)
    build_problem(:sub, a, b, 4)
  end

  def generate_problem(5) do
    # Tens: multiples of 10, sum <= 100
    a = Enum.random(1..9) * 10
    b = Enum.random(1..((100 - a) |> div(10))) * 10
    build_problem(:add, a, b, 5)
  end

  def generate_problem(6) do
    # Tens: subtract multiples of 10
    a = Enum.random(2..10) * 10
    b = Enum.random(1..(div(a, 10) - 1)) * 10
    build_problem(:sub, a, b, 6)
  end

  def generate_problem(7) do
    # Two-digit addition, no carry (units sum < 10, tens sum < 10)
    a_tens = Enum.random(1..5)
    b_tens = Enum.random(1..(8 - a_tens))
    a_ones = Enum.random(1..5)
    b_ones = Enum.random(1..(9 - a_ones))
    a = a_tens * 10 + a_ones
    b = b_tens * 10 + b_ones
    build_problem(:add, a, b, 7)
  end

  def generate_problem(8) do
    # Two-digit subtraction, no borrow (a_ones >= b_ones, a_tens >= b_tens)
    a_tens = Enum.random(3..8)
    b_tens = Enum.random(1..(a_tens - 1))
    a_ones = Enum.random(2..9)
    b_ones = Enum.random(1..a_ones)
    a = a_tens * 10 + a_ones
    b = b_tens * 10 + b_ones
    build_problem(:sub, a, b, 8)
  end

  def generate_problem(9) do
    # Two-digit addition WITH carry (units sum >= 10)
    a_ones = Enum.random(3..9)
    b_ones = Enum.random((10 - a_ones + 1)..9)
    a_tens = Enum.random(1..6)
    b_tens = Enum.random(1..(8 - a_tens))
    a = a_tens * 10 + a_ones
    b = b_tens * 10 + b_ones
    build_problem(:add, a, b, 9)
  end

  def generate_problem(10) do
    # Two-digit subtraction WITH borrow (a_ones < b_ones)
    a_tens = Enum.random(3..9)
    a_ones = Enum.random(0..4)
    b_ones = Enum.random((a_ones + 1)..9)
    b_tens = Enum.random(1..(a_tens - 1))
    a = a_tens * 10 + a_ones
    b = b_tens * 10 + b_ones
    build_problem(:sub, a, b, 10)
  end

  def generate_problem(11) do
    # Multiplication: ×2, ×5, ×10
    factor = Enum.random([2, 5, 10])
    other = Enum.random(1..10)

    # Randomly swap order for variety
    {a, b} = if :rand.uniform() > 0.5, do: {other, factor}, else: {factor, other}
    build_problem(:mul, a, b, 11)
  end

  def generate_problem(12) do
    # Multiplication: ×3, ×4, ×6, ×7, ×8, ×9
    factor = Enum.random([3, 4, 6, 7, 8, 9])
    other = Enum.random(2..9)
    {a, b} = if :rand.uniform() > 0.5, do: {other, factor}, else: {factor, other}
    build_problem(:mul, a, b, 12)
  end

  # Not intended for use outside this module
  # Builds the canonical problem map given operation/inputs/level.
  def build_problem(op, a, b, level) do
    %{
      question: render_question(op, a, b),
      answer: apply_op(op, a, b),
      level: level,
      a: a,
      b: b,
      op: op
    }
  end

  def apply_op(:add, a, b), do: a + b
  def apply_op(:sub, a, b), do: a - b
  def apply_op(:mul, a, b), do: a * b

  def render_question(:add, a, b), do: "#{a} + #{b}"
  def render_question(:sub, a, b), do: "#{a} − #{b}"
  def render_question(:mul, a, b), do: "#{a} × #{b}"

  # Operation swapped to provide a misleading-but-plausible distractor.
  def swap_op(:add), do: :sub
  def swap_op(:sub), do: :add
  def swap_op(:mul), do: :add

  @doc """
  Generate four shuffled multiple-choice options for a problem.

  Guarantees the correct answer is included, plus:
    * one distractor reachable by changing one input by 1
    * one distractor reachable by switching the operation
    * one extra nearby distractor

  All choices are non-negative integers and distinct.
  """
  def generate_choices(%{a: a, b: b, op: op, answer: answer}) do
    by_one_candidates =
      [
        apply_op(op, a + 1, b),
        apply_op(op, a, b + 1),
        apply_op(op, max(a - 1, 0), b),
        apply_op(op, a, max(b - 1, 0))
      ]
      |> Enum.filter(fn x -> x >= 0 and x != answer end)
      |> Enum.uniq()

    d_one =
      case by_one_candidates do
        [] -> answer + 1
        list -> Enum.random(list)
      end

    swapped = apply_op(swap_op(op), a, b)

    d_swap =
      if swapped >= 0 and swapped != answer and swapped != d_one do
        swapped
      else
        fallback =
          [
            apply_op(op, a + 2, b),
            apply_op(op, a, b + 2),
            apply_op(op, max(a - 2, 0), b),
            apply_op(op, a, max(b - 2, 0))
          ]
          |> Enum.find(fn x -> x >= 0 and x != answer and x != d_one end)

        fallback || answer + 2
      end

    d_extra =
      [answer + 1, answer - 1, answer + 2, answer - 2, answer + 5, answer + 10]
      |> Enum.filter(fn x -> x >= 0 and x not in [answer, d_one, d_swap] end)
      |> case do
        [] -> answer + 3
        list -> Enum.random(list)
      end

    Enum.shuffle([answer, d_one, d_swap, d_extra])
  end

  @doc """
  Generate a sequence of math problems using weighted distribution.
  Returns a list of problem maps suitable for JSON encoding (includes choices).
  """
  def generate_game_sequence(highest_level, count \\ 200) do
    for _i <- 1..count do
      level = pick_level(highest_level)
      problem = generate_problem(level)
      choices = generate_choices(problem)

      %{
        "question" => problem.question,
        "answer" => problem.answer,
        "level" => problem.level,
        "choices" => choices
      }
    end
  end
end
