defmodule LestrarvinurPhoenix.Constants do
  @moduledoc """
  Application constants including word lists, trophies, and encouragement messages.
  """

  # List colors (categories)
  @list_colors %{
    yellow: "Guli",
    blue: "Blái",
    red: "Rauði",
    green: "Græni",
    purple: "Fjólublái",
    orange: "Appelsínuguli",
    pink: "Bleiki"
  }

  @original_word_lists %{
    yellow: [
      "en",
      "því",
      "þegar",
      "eru",
      "upp",
      "um",
      "það",
      "á",
      "ég",
      "við",
      "í",
      "hún",
      "af",
      "þá",
      "til",
      "var",
      "nú",
      "og",
      "er",
      "að",
      "hann",
      "svo",
      "sem",
      "ekki"
    ],
    blue: [
      "vorum",
      "komum",
      "inn",
      "þau",
      "segir",
      "þeim",
      "kom",
      "þér",
      "mikið",
      "hvar",
      "eða",
      "vera",
      "þess",
      "honum",
      "frá",
      "of",
      "sig",
      "vel",
      "fara",
      "fram",
      "stað",
      "þetta"
    ],
    red: [
      "sér",
      "hjá",
      "fór",
      "heim",
      "út",
      "frá",
      "hana",
      "þó",
      "þar",
      "eftir",
      "mér",
      "úr",
      "þeir",
      "með",
      "fórum",
      "voru",
      "verið",
      "mig",
      "þú",
      "fyrir",
      "okkur"
    ],
    green: [
      "saman",
      "hafði",
      "mjög",
      "hvað",
      "koma",
      "sagði",
      "niður",
      "nema",
      "oft",
      "þarna",
      "því að",
      "okkur",
      "þær",
      "eins og",
      "aftur",
      "allt",
      "varð",
      "hafa",
      "síðan",
      "yfir",
      "henni"
    ]
  }

  # Read the 500-word list at compile time, drop words already in the original
  # four lists, and split the remainder deterministically into purple/orange
  # using a stable hash so the assignment doesn't change across rebuilds.
  @top500_path Path.expand("../../500ord.txt", __DIR__)
  @external_resource @top500_path

  @existing_words @original_word_lists
                  |> Map.values()
                  |> List.flatten()
                  |> MapSet.new()

  @new_500_words @top500_path
                 |> File.read!()
                 |> String.split("\n", trim: true)
                 |> Enum.map(fn line ->
                   case String.split(line, ". ", parts: 2) do
                     [_, word] -> word |> String.trim() |> String.downcase()
                     _ -> nil
                   end
                 end)
                 |> Enum.reject(&is_nil/1)
                 |> Enum.uniq()
                 |> Enum.reject(&MapSet.member?(@existing_words, &1))

  # Read the phrasebook file (frasar_og_ord.txt) at compile time. Lines starting
  # with # are headers/comments. Entries containing whitespace are phrases and
  # become the pink list; single words are merged into the purple/orange split.
  @frasar_path Path.expand("../../frasar_og_ord.txt", __DIR__)
  @external_resource @frasar_path

  @frasar_entries @frasar_path
                  |> File.read!()
                  |> String.split("\n", trim: true)
                  |> Enum.map(&String.trim/1)
                  |> Enum.reject(fn line -> line == "" or String.starts_with?(line, "#") end)
                  |> Enum.uniq()

  @phrase_list Enum.filter(@frasar_entries, &String.contains?(&1, " "))

  @frasar_single_words @frasar_entries
                       |> Enum.reject(&String.contains?(&1, " "))
                       |> Enum.map(&String.downcase/1)
                       |> Enum.uniq()
                       |> Enum.reject(&MapSet.member?(@existing_words, &1))
                       |> Enum.reject(&(&1 in @new_500_words))

  @split_words @new_500_words ++ @frasar_single_words

  @purple_words Enum.filter(@split_words, fn w -> rem(:erlang.phash2(w), 2) == 0 end)
  @orange_words Enum.filter(@split_words, fn w -> rem(:erlang.phash2(w), 2) == 1 end)

  @word_lists Map.merge(@original_word_lists, %{
                purple: @purple_words,
                orange: @orange_words,
                pink: @phrase_list
              })

  # Trophy definitions
  @trophies [
    %{
      id: "t_50",
      threshold: 100,
      name: "Byrjandi",
      color: "#fbbf24"
    },
    %{
      id: "t_100",
      threshold: 200,
      name: "Lestrarhestur",
      color: "#34d399"
    },
    %{
      id: "t_200",
      threshold: 400,
      name: "Snillingur",
      color: "#60a5fa"
    },
    %{
      id: "t_300",
      threshold: 600,
      name: "Meistari",
      color: "#818cf8"
    },
    %{
      id: "t_400",
      threshold: 800,
      name: "Stjarna",
      color: "#a78bfa"
    },
    %{
      id: "t_500",
      threshold: 1000,
      name: "Ofurhetja",
      color: "#f472b6"
    },
    %{
      id: "t_750",
      threshold: 1500,
      name: "Galdramaður",
      color: "#fb7185"
    },
    %{
      id: "t_1000",
      threshold: 2000,
      name: "Goðsögn",
      color: "#fcd34d"
    }
  ]

  # 30 encouragement messages (reduced from the original 10 static ones, expanded to 30)
  @encouragements [
    "Vel gert!",
    "Frábær lestur!",
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
    "Þú ert hetja!",
    "Ég er stoltur af þér!"
  ]

  # Prestige threshold
  # Set to 2000 for testing (normally 10_000)
  @prestige_threshold 2_000

  # Admin username
  @admin_username "joi@joisig.com"

  def list_colors, do: @list_colors
  def word_lists, do: @word_lists
  def trophies, do: @trophies
  def encouragements, do: @encouragements
  def prestige_threshold, do: @prestige_threshold
  def admin_username, do: @admin_username

  @doc """
  Get all words as a flat list with their category.
  Returns list of %{word: string, category: atom}
  """
  def all_words do
    Enum.flat_map(@word_lists, fn {category, words} ->
      Enum.map(words, fn word ->
        %{word: word, category: category}
      end)
    end)
  end

  @doc """
  Get words for a specific category.
  """
  def words_by_category(category) when is_atom(category) do
    Map.get(@word_lists, category, [])
  end

  @doc """
  True when an entry is a phrase (2+ words) rather than a single word.
  """
  def phrase?(entry), do: String.contains?(entry, " ")

  @doc """
  Get a trophy by ID.
  """
  def get_trophy(trophy_id) do
    Enum.find(@trophies, fn t -> t.id == trophy_id end)
  end

  @doc """
  Get a random encouragement message.
  """
  def random_encouragement do
    Enum.random(@encouragements)
  end

  @doc """
  Get encouragement by index (0-29).
  """
  def get_encouragement(index) when index >= 0 and index < 30 do
    Enum.at(@encouragements, index)
  end

  @doc """
  Check if a username is the admin.
  """
  def admin?(username) do
    username == @admin_username
  end

  @doc """
  Get color name for a category.
  """
  def color_name(category) when is_atom(category) do
    Map.get(@list_colors, category, "")
  end
end
