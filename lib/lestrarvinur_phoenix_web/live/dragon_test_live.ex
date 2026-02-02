defmodule LestrarvinurPhoenixWeb.DragonTestLive do
  @moduledoc """
  Test page for the Dragon Fling minigame. Visit /dragon-test to try it out.
  """
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.Constants

  def mount(_params, _session, socket) do
    # Generate test words for the dragon game
    test_words = generate_test_words(100)

    # Start with first 6 words visible
    {initial_visible, remaining} = Enum.split(test_words, 6)

    {:ok,
     socket
     |> assign(:dragon_mode, true)
     |> assign(:dragon_words_queue, remaining)
     |> assign(:dragon_visible_words, initial_visible)
     |> assign(:dragon_words_flung, 0)
     |> assign(:dragon_total_words, length(test_words))
     |> assign(:dragon_hit_active, false)
     |> assign(:dragon_hit_text, "POW!")
     |> assign(:dragon_hit_pos, {50, 50})}
  end

  def handle_event("word_flung", %{"word_id" => word_id}, socket) do
    # Remove the flung word from visible words
    visible = Enum.reject(socket.assigns.dragon_visible_words, fn w -> w.id == word_id end)
    flung_count = socket.assigns.dragon_words_flung + 1

    # Random hit effect text and position
    hit_text = Enum.random(dragon_hit_sounds())
    hit_pos = {Enum.random(15..85), Enum.random(15..85)}

    socket =
      socket
      |> assign(:dragon_visible_words, visible)
      |> assign(:dragon_words_flung, flung_count)
      |> assign(:dragon_hit_active, true)
      |> assign(:dragon_hit_text, hit_text)
      |> assign(:dragon_hit_pos, hit_pos)

    # Schedule hit animation to clear and next word to appear
    Process.send_after(self(), {:clear_hit, word_id}, 900)
    Process.send_after(self(), :next_dragon_word, 100)

    {:noreply, socket}
  end

  def handle_event("skip_dragon_game", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def handle_info({:clear_hit, _word_id}, socket) do
    {:noreply, assign(socket, :dragon_hit_active, false)}
  end

  def handle_info(:next_dragon_word, socket) do
    queue = socket.assigns.dragon_words_queue
    visible = socket.assigns.dragon_visible_words

    cond do
      length(visible) >= 6 or queue == [] ->
        if queue == [] and visible == [] do
          # Game complete, redirect to home
          {:noreply, redirect(socket, to: ~p"/")}
        else
          {:noreply, socket}
        end

      true ->
        [next_word | rest] = queue
        new_visible = visible ++ [next_word]

        {:noreply,
         socket
         |> assign(:dragon_words_queue, rest)
         |> assign(:dragon_visible_words, new_visible)}
    end
  end

  # Not intended for use outside this module
  def dragon_hit_sounds do
    ["KA-POW!", "BLAM!", "BONG!", "POW!", "THUD!", "RAT-TAT-TAT!", "BIFF!", "BONK!", "KA-RACK!"]
  end

  # Not intended for use outside this module
  def generate_test_words(count) do
    categories = [:yellow, :blue, :red, :green]

    1..count
    |> Enum.map(fn idx ->
      category = Enum.random(categories)
      words = Constants.words_by_category(category)
      word = Enum.random(words)
      %{id: "dw-#{idx}", word: word, category: category}
    end)
  end

  def render(assigns) do
    {hit_x, hit_y} = assigns.dragon_hit_pos

    assigns =
      assigns
      |> assign(:hit_x, hit_x)
      |> assign(:hit_y, hit_y)

    ~H"""
    <div
      id="dragon-game"
      class="h-full w-full flex flex-col overflow-hidden"
      style="background: linear-gradient(135deg, #4c1d95 0%, #7c3aed 50%, #6366f1 100%);"
      phx-hook="DragonFling"
    >
      <!-- Skip button -->
      <button
        phx-click="skip_dragon_game"
        class="absolute top-4 right-4 z-20 bg-white/20 hover:bg-white/30 backdrop-blur rounded-full p-3 text-white transition-all"
        aria-label="Skip game"
      >
        <.icon name="hero-x-mark" class="w-6 h-6" />
      </button>
      
    <!-- Progress counter -->
      <div class="absolute top-4 left-4 z-20 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white font-bold">
        {@dragon_words_flung} / {@dragon_total_words}
      </div>
      
    <!-- Dragon area (60% height at top) -->
      <div class="h-[60%] flex items-start justify-center pt-16 relative" id="dragon-target">
        <!-- Dragon image with bob animation -->
        <div class="dragon-container relative w-full h-full flex items-center justify-center">
          <img
            src="/images/dragon.jpg"
            alt="Dragon"
            class="max-h-full max-w-[80%] object-contain dragon-bob rounded-2xl shadow-2xl"
          />
          <!-- Hit effect at random position -->
          <%= if @dragon_hit_active do %>
            <div
              class="absolute pow-burst pointer-events-none z-10"
              style={"left: #{@hit_x}%; top: #{@hit_y}%; transform: translate(-50%, -50%);"}
            >
              <.comic_burst text={@dragon_hit_text} />
            </div>
          <% end %>
        </div>
      </div>
      
    <!-- Word cards area (40% height at bottom) -->
      <div class="h-[40%] relative flex flex-wrap items-center justify-center gap-3 px-4 pb-4 content-center">
        <%= for word <- @dragon_visible_words do %>
          <div
            id={word.id}
            data-word-id={word.id}
            class={"word-flingable bg-white rounded-2xl px-4 py-3 shadow-2xl cursor-grab active:cursor-grabbing select-none word-slide-in #{word_card_color(word.category)}"}
          >
            <span class="text-xl md:text-2xl font-bold text-slate-800">{word.word}</span>
          </div>
        <% end %>
      </div>
      
    <!-- Instructions -->
      <div class="absolute bottom-2 left-0 right-0 text-center text-white/60 text-sm">
        Dragðu orðin upp að drekanum!
      </div>
    </div>
    """
  end

  # Comic burst effect component for hit effects
  defp comic_burst(assigns) do
    ~H"""
    <svg viewBox="0 0 200 200" class="w-32 h-32 md:w-40 md:h-40 drop-shadow-lg">
      <!-- Starburst background -->
      <polygon
        points="100,10 115,60 170,40 135,80 190,100 135,120 170,160 115,140 100,190 85,140 30,160 65,120 10,100 65,80 30,40 85,60"
        fill="#FFD700"
        stroke="#FF8C00"
        stroke-width="3"
      />
      <!-- Inner burst -->
      <polygon
        points="100,30 112,65 155,50 128,82 175,100 128,118 155,150 112,135 100,170 88,135 45,150 72,118 25,100 72,82 45,50 88,65"
        fill="#FFEC00"
        stroke="#FFB800"
        stroke-width="2"
      />
      <!-- Text -->
      <text
        x="100"
        y="108"
        font-family="Impact, Arial Black, sans-serif"
        font-size={if String.length(@text) > 6, do: "22", else: "28"}
        font-weight="bold"
        fill="#CC0000"
        text-anchor="middle"
        stroke="#000"
        stroke-width="1"
      >
        {@text}
      </text>
    </svg>
    """
  end

  # Color classes for word cards in dragon game
  defp word_card_color(:yellow), do: "border-4 border-yellow-400"
  defp word_card_color(:blue), do: "border-4 border-blue-400"
  defp word_card_color(:red), do: "border-4 border-red-400"
  defp word_card_color(:green), do: "border-4 border-green-400"
  defp word_card_color(_), do: "border-4 border-yellow-400"
end
