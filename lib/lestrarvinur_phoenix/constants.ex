defmodule LestrarvinurPhoenix.Constants do
  @moduledoc """
  Application constants including word lists, trophies, and encouragement messages.
  """

  # List colors (categories)
  @list_colors %{
    yellow: "Guli",
    blue: "Blái",
    red: "Rauði",
    green: "Græni"
  }

  # Word lists organized by color/category
  @word_lists %{
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
  @prestige_threshold 2_000  # Set to 2000 for testing (normally 10_000)

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
