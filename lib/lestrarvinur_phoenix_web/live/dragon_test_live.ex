defmodule LestrarvinurPhoenixWeb.DragonTestLive do
  @moduledoc """
  Test page for the Dragon Fling minigame. Visit /dragon-test to try it out.
  """
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.Constants

  def mount(_params, _session, socket) do
    # Generate test words for the dragon game (35 longest words)
    test_words = generate_test_words(35)

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
     |> assign(:dragon_hit_pos, {50, 50})
     |> assign(:dragon_health, 20)
     |> assign(:dragon_max_health, 20)
     |> assign(:dragon_exploding, false)}
  end

  def handle_event("word_flung", params, socket) do
    word_id = params["word_id"]
    is_hit = params["is_hit"] == true
    hit_x = params["hit_x"] || Enum.random(20..80)
    hit_y = params["hit_y"] || Enum.random(20..80)

    # Remove the flung word from visible words
    visible = Enum.reject(socket.assigns.dragon_visible_words, fn w -> w.id == word_id end)
    flung_count = socket.assigns.dragon_words_flung + 1

    # Only decrease health on actual hits
    health =
      if is_hit do
        max(0, socket.assigns.dragon_health - 1)
      else
        socket.assigns.dragon_health
      end

    # Only show POW effect on actual hits
    socket =
      socket
      |> assign(:dragon_visible_words, visible)
      |> assign(:dragon_words_flung, flung_count)
      |> assign(:dragon_health, health)

    socket =
      if is_hit do
        hit_text = Enum.random(dragon_hit_sounds())

        socket
        |> assign(:dragon_hit_active, true)
        |> assign(:dragon_hit_text, hit_text)
        |> assign(:dragon_hit_pos, {hit_x, hit_y})
      else
        socket
      end

    # Schedule hit animation to clear (if hit) and next word to appear
    if is_hit do
      Process.send_after(self(), {:clear_hit, word_id}, 900)
    end

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
    health = socket.assigns.dragon_health

    cond do
      # Dragon defeated - trigger explosion!
      health == 0 and not socket.assigns.dragon_exploding ->
        socket = assign(socket, :dragon_exploding, true)
        Process.send_after(self(), :dragon_explosion_done, 2000)
        {:noreply, socket}

      # Game over (out of words) - just redirect, no explosion
      queue == [] and visible == [] ->
        {:noreply, redirect(socket, to: ~p"/")}

      # Can add more words
      length(visible) < 6 and queue != [] ->
        [next_word | rest] = queue
        new_visible = visible ++ [next_word]

        {:noreply,
         socket
         |> assign(:dragon_words_queue, rest)
         |> assign(:dragon_visible_words, new_visible)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info(:dragon_explosion_done, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  # Not intended for use outside this module
  def dragon_hit_sounds do
    ["KA-POW!", "BLAM!", "BONG!", "POW!", "THUD!", "RAT-TAT-TAT!", "BIFF!", "BONK!", "KA-RACK!"]
  end

  # Not intended for use outside this module
  # Generates test words by picking the longest words from all categories
  def generate_test_words(count) do
    all_words =
      [:yellow, :blue, :red, :green]
      |> Enum.flat_map(fn category ->
        Constants.words_by_category(category)
        |> Enum.map(fn word -> {word, category} end)
      end)
      |> Enum.sort_by(fn {word, _cat} -> -String.length(word) end)
      |> Enum.take(count)
      |> Enum.shuffle()

    all_words
    |> Enum.with_index()
    |> Enum.map(fn {{word, category}, idx} ->
      %{id: "dw-#{idx}", word: word, category: category}
    end)
  end

  def render(assigns) do
    {hit_x, hit_y} = assigns.dragon_hit_pos

    assigns =
      assigns
      |> assign(:hit_x, hit_x)
      |> assign(:hit_y, hit_y)
      |> assign(:health_percent, round(assigns.dragon_health / assigns.dragon_max_health * 100))
      |> assign(:health_color, health_bar_color(assigns.dragon_health, assigns.dragon_max_health))

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
      <div class="h-[60%] flex flex-col items-center justify-start pt-14 relative" id="dragon-target">
        <!-- Health bar -->
        <div class="w-48 md:w-64 mb-2">
          <div class="h-4 bg-gray-800 rounded-full overflow-hidden border-2 border-white/30 shadow-lg">
            <div
              class={"h-full transition-all duration-300 #{@health_color}"}
              style={"width: #{@health_percent}%;"}
            >
            </div>
          </div>
        </div>
        
    <!-- Dragon image with bob animation -->
        <div class="dragon-container relative flex-1 w-full flex items-center justify-center">
          <img
            src="/images/dragon.jpg"
            alt="Dragon"
            class={"max-h-full max-w-[80%] object-contain rounded-2xl shadow-2xl #{if @dragon_exploding, do: "dragon-defeated", else: "dragon-bob"}"}
          />
          <!-- Hit effect at random position -->
          <%= if @dragon_hit_active and not @dragon_exploding do %>
            <div
              class="absolute pow-burst pointer-events-none z-10"
              style={"left: #{@hit_x}%; top: #{@hit_y}%; transform: translate(-50%, -50%);"}
            >
              <.comic_burst text={@dragon_hit_text} />
            </div>
          <% end %>
          
    <!-- Final explosion -->
          <%= if @dragon_exploding do %>
            <div class="absolute inset-0 flex items-center justify-center explosion-container">
              <.mega_explosion />
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
        <%= if @dragon_exploding do %>
          Vel gert!
        <% else %>
          Dragðu orðin upp að drekanum!
        <% end %>
      </div>
    </div>
    """
  end

  # Health bar color based on health percentage
  defp health_bar_color(health, max_health) do
    percent = health / max_health * 100

    cond do
      percent > 60 -> "bg-green-500"
      percent > 30 -> "bg-yellow-500"
      true -> "bg-red-500"
    end
  end

  # Mega explosion effect for defeating the dragon
  defp mega_explosion(assigns) do
    ~H"""
    <div class="mega-explosion">
      <svg viewBox="0 0 400 400" class="w-80 h-80 md:w-96 md:h-96">
        <!-- Outer burst -->
        <polygon
          points="200,20 220,100 300,60 250,130 380,150 250,180 300,250 220,220 200,300 180,220 100,250 150,180 20,150 150,130 100,60 180,100"
          fill="#FFD700"
          stroke="#FF6600"
          stroke-width="4"
          class="explosion-outer"
        />
        <!-- Middle burst -->
        <polygon
          points="200,50 215,110 270,80 240,140 340,160 240,185 270,230 215,205 200,270 185,205 130,230 160,185 60,160 160,140 130,80 185,110"
          fill="#FFEC00"
          stroke="#FF8C00"
          stroke-width="3"
          class="explosion-middle"
        />
        <!-- Inner burst -->
        <polygon
          points="200,80 212,120 250,100 230,145 300,160 230,175 250,210 212,195 200,240 188,195 150,210 170,175 100,160 170,145 150,100 188,120"
          fill="#FFFFFF"
          stroke="#FFD700"
          stroke-width="2"
          class="explosion-inner"
        />
        <!-- KA-POW text -->
        <text
          x="200"
          y="170"
          font-family="Impact, Arial Black, sans-serif"
          font-size="48"
          font-weight="bold"
          fill="#CC0000"
          text-anchor="middle"
          stroke="#000"
          stroke-width="2"
        >
          KA-POW!
        </text>
      </svg>
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
