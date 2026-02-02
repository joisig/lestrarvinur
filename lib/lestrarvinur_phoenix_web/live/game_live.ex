defmodule LestrarvinurPhoenixWeb.GameLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.{Accounts, Constants}

  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_user(username) do
      nil ->
        {:ok, redirect(socket, to: ~p"/")}

      user ->
        # Restore saved sequence or generate new one
        saved_sequence = Accounts.User.decode_sequence(user)

        {sequence, current_index} =
          if saved_sequence != [] and user.current_word_index < length(saved_sequence) do
            # Convert string keys back to atom keys for use in the LiveView
            restored_sequence =
              Enum.map(saved_sequence, fn item ->
                %{word: item["word"], category: String.to_atom(item["category"])}
              end)

            {restored_sequence, user.current_word_index}
          else
            # Generate new sequence and save it
            new_sequence = generate_game_sequence()
            encoded_sequence = Accounts.User.encode_sequence(new_sequence)

            Accounts.update_user(user, %{
              shuffled_sequence: encoded_sequence,
              current_word_index: 0
            })

            # Convert to atom keys for LiveView
            atom_sequence =
              Enum.map(new_sequence, fn item ->
                %{word: item["word"], category: String.to_atom(item["category"])}
              end)

            {atom_sequence, 0}
          end

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:sequence, sequence)
         |> assign(:current_word_index, current_index)
         |> assign(:session_count, 0)
         |> assign(:show_encouragement, false)
         |> assign(:encouragement_text, "")
         |> assign(:just_unlocked, nil)
         |> assign(:current_word, Enum.at(sequence, current_index))
         # Dragon fling minigame state
         |> assign(:recent_words, [])
         |> assign(:dragon_mode, false)
         |> assign(:dragon_words_queue, [])
         |> assign(:dragon_visible_words, [])
         |> assign(:dragon_words_flung, 0)
         |> assign(:dragon_total_words, 0)
         |> assign(:dragon_hit_active, false)
         |> assign(:dragon_hit_text, "POW!")
         |> assign(:dragon_hit_pos, {50, 50})
         |> assign(:dragon_health, 100)
         |> assign(:dragon_exploding, false)
         |> assign(:pending_trophy, nil)}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/")}
  end

  def handle_event("exit", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/dashboard?username=#{socket.assigns.user.username}")}
  end

  def handle_event("next", _params, socket) do
    cond do
      socket.assigns.dragon_mode ->
        # Don't advance during dragon mode, clicks should be handled by the game
        {:noreply, socket}

      socket.assigns.show_encouragement or socket.assigns.just_unlocked ->
        # Dismiss modal
        {:noreply,
         socket
         |> assign(:show_encouragement, false)
         |> assign(:just_unlocked, nil)}

      true ->
        handle_word_completed(socket)
    end
  end

  def handle_event("word_flung", params, socket) do
    word_id = params["word_id"]
    # Use hit position from JS if provided, otherwise random
    hit_x = params["hit_x"] || Enum.random(20..80)
    hit_y = params["hit_y"] || Enum.random(20..80)

    # Remove the flung word from visible words
    visible = Enum.reject(socket.assigns.dragon_visible_words, fn w -> w.id == word_id end)
    flung_count = socket.assigns.dragon_words_flung + 1
    total = socket.assigns.dragon_total_words

    # Calculate health (drops from 100 to 0)
    health = max(0, 100 - round(flung_count / total * 100))

    # Random hit effect text
    hit_text = Enum.random(dragon_hit_sounds())

    socket =
      socket
      |> assign(:dragon_visible_words, visible)
      |> assign(:dragon_words_flung, flung_count)
      |> assign(:dragon_hit_active, true)
      |> assign(:dragon_hit_text, hit_text)
      |> assign(:dragon_hit_pos, {hit_x, hit_y})
      |> assign(:dragon_health, health)

    # Schedule hit animation to clear and next word to appear
    Process.send_after(self(), {:clear_hit, word_id}, 900)
    Process.send_after(self(), :next_dragon_word, 100)

    {:noreply, socket}
  end

  def handle_event("skip_dragon_game", _params, socket) do
    # Exit dragon mode and check for pending trophy
    socket =
      socket
      |> assign(:dragon_mode, false)
      |> assign(:dragon_words_queue, [])
      |> assign(:dragon_visible_words, [])
      |> assign(:dragon_words_flung, 0)
      |> assign(:dragon_total_words, 0)
      |> assign(:dragon_hit_active, false)

    # Show pending trophy if any
    socket =
      if socket.assigns.pending_trophy do
        socket
        |> assign(:just_unlocked, socket.assigns.pending_trophy)
        |> assign(:pending_trophy, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_event("speak_word", _params, socket) do
    # Audio playback is handled client-side via JavaScript
    # We just need to provide the audio URL if available
    {:noreply, socket}
  end

  def handle_info({:clear_hit, _word_id}, socket) do
    {:noreply, assign(socket, :dragon_hit_active, false)}
  end

  def handle_info(:next_dragon_word, socket) do
    queue = socket.assigns.dragon_words_queue
    visible = socket.assigns.dragon_visible_words

    # Only add a new word if we have fewer than 6 visible and queue has words
    cond do
      length(visible) >= 6 or queue == [] ->
        # Check if game is complete
        if queue == [] and visible == [] do
          # Trigger explosion!
          socket = assign(socket, :dragon_exploding, true)
          # Schedule end of explosion and game exit
          Process.send_after(self(), :dragon_explosion_done, 2000)
          {:noreply, socket}
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

  def handle_info(:dragon_explosion_done, socket) do
    # Dragon game complete, exit and show trophy if pending
    socket =
      socket
      |> assign(:dragon_mode, false)
      |> assign(:dragon_words_flung, 0)
      |> assign(:dragon_total_words, 0)
      |> assign(:dragon_health, 100)
      |> assign(:dragon_exploding, false)

    socket =
      if socket.assigns.pending_trophy do
        socket
        |> assign(:just_unlocked, socket.assigns.pending_trophy)
        |> assign(:pending_trophy, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  # Not intended for use outside this module
  def handle_word_completed(socket) do
    user = socket.assigns.user
    new_streak = socket.assigns.session_count + 1
    current_word = socket.assigns.current_word
    old_progress = rem(user.total_words_read, Constants.prestige_threshold())

    # Track recent words for dragon game (keep last 100)
    recent_words = [current_word | socket.assigns.recent_words] |> Enum.take(100)

    # Update user in database
    {:ok, updated_user} = Accounts.increment_words_read(user)
    new_progress = rem(updated_user.total_words_read, Constants.prestige_threshold())
    cycle = div(updated_user.total_words_read, Constants.prestige_threshold())

    # Check if we just crossed a trophy threshold
    # Handle wrapping: if new_progress < old_progress, we wrapped from cycle boundary
    wrapped = new_progress < old_progress

    newly_unlocked =
      Enum.find(Constants.trophies(), fn trophy ->
        cond do
          wrapped ->
            # We crossed the cycle boundary, check if threshold is between old_progress and threshold
            old_progress < trophy.threshold

          true ->
            # Normal case: check if we crossed the threshold
            old_progress < trophy.threshold and new_progress >= trophy.threshold
        end
      end)

    # Check if we hit a 100-word milestone for dragon game
    dragon_milestone =
      rem(updated_user.total_words_read, 100) == 0 and updated_user.total_words_read > 0

    # Update socket with new user
    socket =
      socket
      |> assign(:user, updated_user)
      |> assign(:recent_words, recent_words)

    # If dragon milestone, start dragon game (trophy will be shown after)
    socket =
      if dragon_milestone do
        # Select the 30 longest words from recent words, then shuffle
        dragon_words =
          recent_words
          |> Enum.sort_by(fn w -> -String.length(w.word) end)
          |> Enum.take(30)
          |> Enum.shuffle()
          |> Enum.with_index()
          |> Enum.map(fn {word, idx} -> Map.put(word, :id, "dw-#{idx}") end)

        # Start with first 6 words visible
        {initial_visible, remaining} = Enum.split(dragon_words, 6)

        socket
        |> assign(:dragon_mode, true)
        |> assign(:dragon_words_queue, remaining)
        |> assign(:dragon_visible_words, initial_visible)
        |> assign(:dragon_words_flung, 0)
        |> assign(:dragon_total_words, length(dragon_words))
        |> assign(:dragon_hit_active, false)
        |> then(fn s ->
          # Store trophy to show after dragon game if applicable
          if newly_unlocked do
            multiplier = if wrapped, do: cycle, else: cycle + 1

            assign(s, :pending_trophy, newly_unlocked)
            |> assign(:trophy_multiplier, multiplier)
          else
            s
          end
        end)
      else
        # No dragon game, handle trophy/encouragement normally
        socket
        |> then(fn s ->
          if newly_unlocked do
            multiplier = if wrapped, do: cycle, else: cycle + 1

            s
            |> assign(:just_unlocked, newly_unlocked)
            |> assign(:trophy_multiplier, multiplier)
          else
            s
          end
        end)
        |> then(fn s ->
          # Show encouragement every 10 words, if no trophy and no dragon game
          if newly_unlocked == nil and rem(new_streak, 10) == 0 do
            encouragement = Constants.random_encouragement()

            s
            |> assign(:show_encouragement, true)
            |> assign(:encouragement_text, encouragement)
          else
            s
          end
        end)
      end

    # Move to next word
    next_index = socket.assigns.current_word_index + 1

    {next_index, sequence, final_user} =
      if next_index >= length(socket.assigns.sequence) do
        # Completed full cycle, reshuffle and restart
        new_sequence = generate_game_sequence()
        encoded_sequence = Accounts.User.encode_sequence(new_sequence)

        # Save new sequence and reset index
        {:ok, user_with_new_sequence} =
          Accounts.update_user(updated_user, %{
            shuffled_sequence: encoded_sequence,
            current_word_index: 0
          })

        # Convert to atom keys for LiveView
        atom_sequence =
          Enum.map(new_sequence, fn item ->
            %{word: item["word"], category: String.to_atom(item["category"])}
          end)

        {0, atom_sequence, user_with_new_sequence}
      else
        # Continue with current sequence, just update the index
        {:ok, user_with_new_index} =
          Accounts.update_user(updated_user, %{current_word_index: next_index})

        {next_index, socket.assigns.sequence, user_with_new_index}
      end

    {:noreply,
     socket
     |> assign(:user, final_user)
     |> assign(:session_count, new_streak)
     |> assign(:current_word_index, next_index)
     |> assign(:sequence, sequence)
     |> assign(:current_word, Enum.at(sequence, next_index))}
  end

  # Not intended for use outside this module
  def dragon_hit_sounds do
    ["KA-POW!", "BLAM!", "BONG!", "POW!", "THUD!", "RAT-TAT-TAT!", "BIFF!", "BONK!", "KA-RACK!"]
  end

  # Not intended for use outside this module
  defp generate_game_sequence do
    yellow = Constants.words_by_category(:yellow)
    red = Constants.words_by_category(:red)
    green = Constants.words_by_category(:green)
    blue = Constants.words_by_category(:blue)

    (Enum.shuffle(yellow) ++
       Enum.shuffle(red) ++
       Enum.shuffle(green) ++
       Enum.shuffle(blue))
    |> Enum.map(fn word ->
      %{"word" => word, "category" => Atom.to_string(get_category(word))}
    end)
  end

  # Not intended for use outside this module
  defp get_category(word) do
    cond do
      word in Constants.words_by_category(:yellow) -> :yellow
      word in Constants.words_by_category(:blue) -> :blue
      word in Constants.words_by_category(:red) -> :red
      word in Constants.words_by_category(:green) -> :green
      true -> :yellow
    end
  end

  def render(assigns) do
    ~H"""
    <div
      phx-click="next"
      class={"h-full w-full flex flex-col relative transition-colors duration-500 ease-in-out #{bg_color(@current_word.category)}"}
    >
      <!-- Header -->
      <div class="absolute top-0 left-0 right-0 p-4 flex justify-between items-center z-10">
        <button
          phx-click="exit"
          class="bg-white/80 backdrop-blur rounded-full px-4 py-2 font-bold shadow-sm text-slate-600 active:scale-95"
        >
          Hætta
        </button>
        <div class="flex gap-2">
          <div class="bg-white/80 backdrop-blur rounded-full px-4 py-2 font-bold shadow-sm text-slate-600">
            ⭐ {@user.total_words_read}
          </div>
        </div>
      </div>
      <!-- Main Flashcard Area -->
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class={"bg-white w-full max-w-sm aspect-[3/4] rounded-[3rem] shadow-2xl flex flex-col items-center justify-center relative border-8 #{border_color(@current_word.category)} transform transition-all duration-300"}>
          <!-- Word Category Label -->
          <div class={"absolute top-8 text-sm font-black tracking-widest uppercase #{accent_color(@current_word.category)}"}>
            {Constants.color_name(@current_word.category)} listi
          </div>
          <!-- The Word -->
          <h1 class="text-7xl md:text-8xl font-black text-slate-800 text-center select-none">
            {@current_word.word}
          </h1>
          <%!-- Audio Button (commented out for now, will use later) --
          <button
            phx-click="speak_word"
            id="audio-button"
            data-word={@current_word.word}
            data-audio-url={Media.get_word_audio_url(@current_word.word)}
            class="p-6 rounded-full transition-all active:scale-90 shadow-inner bg-slate-100 hover:bg-slate-200 text-slate-600"
            aria-label="Listen to word"
            phx-hook="AudioPlayer"
          >
            <.icon name="hero-speaker-wave" class="h-10 w-10" />
          </button>
          --%>

          <p class="absolute bottom-8 text-slate-300 text-sm font-medium animate-pulse">
            Ýttu á skjáinn
          </p>
        </div>
      </div>
      <!-- Progress Bar -->
      <div class="h-4 bg-slate-200 w-full">
        <div
          class="h-full bg-sky-500 transition-all duration-300"
          style={"width: #{rem(@session_count, 10) * 10}%"}
        >
        </div>
      </div>
      <!-- Encouragement Overlay -->
      <%= if @show_encouragement do %>
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-6">
          <div class="bg-white rounded-3xl p-8 max-w-md w-full text-center shadow-2xl">
            <div class="text-6xl mb-4">🦜</div>
            <h2 class="text-3xl font-bold text-sky-600 mb-4">{@encouragement_text}</h2>
            <p class="text-slate-500 mb-6">Vel gert! 10 orð í röð!</p>
            <div class="text-sm text-slate-400">Ýttu til að halda áfram</div>
          </div>
        </div>
      <% end %>
      <!-- Trophy Unlocked Overlay -->
      <%= if @just_unlocked do %>
        <div class="absolute inset-0 bg-yellow-400/90 backdrop-blur-md z-50 flex items-center justify-center p-6">
          <div class="bg-white rounded-3xl p-8 max-w-md w-full text-center shadow-2xl flex flex-col items-center">
            <h2 class="text-3xl font-black text-yellow-600 mb-2">NÝR BIKAR!</h2>
            <div class="my-8 scale-150">
              <.trophy_icon
                trophy_id={@just_unlocked.id}
                color={@just_unlocked.color}
                size="lg"
                prestige_multiplier={assigns[:trophy_multiplier] || 1}
              />
            </div>
            <h3 class="text-2xl font-bold text-slate-800">{@just_unlocked.name}</h3>
            <p class="text-slate-500 mt-2">
              Þú hefur lesið {@just_unlocked.threshold} orð<%= if assigns[:trophy_multiplier] && @trophy_multiplier > 1 do %>
                (x{@trophy_multiplier})
              <% end %>!
            </p>
            <div class="mt-8 text-sm text-slate-400 font-bold uppercase tracking-widest animate-pulse">
              Ýttu til að halda áfram
            </div>
          </div>
        </div>
      <% end %>
      <!-- Dragon Fling Minigame Overlay -->
      <%= if @dragon_mode do %>
        <.dragon_game_overlay
          visible_words={@dragon_visible_words}
          words_flung={@dragon_words_flung}
          total_words={@dragon_total_words}
          hit_active={@dragon_hit_active}
          hit_text={@dragon_hit_text}
          hit_pos={@dragon_hit_pos}
          health={@dragon_health}
          exploding={@dragon_exploding}
        />
      <% end %>
    </div>
    """
  end

  # Dragon game overlay component
  defp dragon_game_overlay(assigns) do
    {hit_x, hit_y} = assigns.hit_pos

    assigns = assign(assigns, :hit_x, hit_x)
    assigns = assign(assigns, :hit_y, hit_y)
    assigns = assign(assigns, :health_color, health_bar_color(assigns.health))

    ~H"""
    <div
      id="dragon-game"
      class="absolute inset-0 z-50 flex flex-col overflow-hidden"
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
        {@words_flung} / {@total_words}
      </div>
      
    <!-- Dragon area (60% height at top) -->
      <div class="h-[60%] flex flex-col items-center justify-start pt-14 relative" id="dragon-target">
        <!-- Health bar -->
        <div class="w-48 md:w-64 mb-2">
          <div class="h-4 bg-gray-800 rounded-full overflow-hidden border-2 border-white/30 shadow-lg">
            <div
              class={"h-full transition-all duration-300 #{@health_color}"}
              style={"width: #{@health}%;"}
            >
            </div>
          </div>
        </div>
        
    <!-- Dragon image with bob animation -->
        <div class="dragon-container relative flex-1 w-full flex items-center justify-center">
          <img
            src="/images/dragon.jpg"
            alt="Dragon"
            class={"max-h-full max-w-[80%] object-contain rounded-2xl shadow-2xl #{if @exploding, do: "dragon-defeated", else: "dragon-bob"}"}
          />
          <!-- Hit effect at random position -->
          <%= if @hit_active and not @exploding do %>
            <div
              class="absolute pow-burst pointer-events-none z-10"
              style={"left: #{@hit_x}%; top: #{@hit_y}%; transform: translate(-50%, -50%);"}
            >
              <.comic_burst text={@hit_text} />
            </div>
          <% end %>
          
    <!-- Final explosion -->
          <%= if @exploding do %>
            <div class="absolute inset-0 flex items-center justify-center explosion-container">
              <.mega_explosion />
            </div>
          <% end %>
        </div>
      </div>
      
    <!-- Word cards area (40% height at bottom) -->
      <div class="h-[40%] relative flex flex-wrap items-center justify-center gap-3 px-4 pb-4 content-center">
        <%= for word <- @visible_words do %>
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
        <%= if @exploding do %>
          Vel gert!
        <% else %>
          Dragðu orðin upp að drekanum!
        <% end %>
      </div>
    </div>
    """
  end

  # Health bar color based on health percentage
  defp health_bar_color(health) when health > 60, do: "bg-green-500"
  defp health_bar_color(health) when health > 30, do: "bg-yellow-500"
  defp health_bar_color(_health), do: "bg-red-500"

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

  # Background colors for list categories
  defp bg_color(:yellow), do: "bg-yellow-50"
  defp bg_color(:blue), do: "bg-blue-50"
  defp bg_color(:red), do: "bg-red-50"
  defp bg_color(:green), do: "bg-green-50"
  defp bg_color(_), do: "bg-yellow-50"

  # Border colors
  defp border_color(:yellow), do: "border-yellow-200"
  defp border_color(:blue), do: "border-blue-200"
  defp border_color(:red), do: "border-red-200"
  defp border_color(:green), do: "border-green-200"
  defp border_color(_), do: "border-yellow-200"

  # Accent colors
  defp accent_color(:yellow), do: "text-yellow-600"
  defp accent_color(:blue), do: "text-blue-600"
  defp accent_color(:red), do: "text-red-600"
  defp accent_color(:green), do: "text-green-600"
  defp accent_color(_), do: "text-yellow-600"

  # Trophy icon component (reused from dashboard)
  defp trophy_icon(assigns) do
    assigns =
      assigns
      |> assign_new(:size, fn -> "md" end)
      |> assign_new(:is_locked, fn -> false end)
      |> assign_new(:prestige_multiplier, fn -> 1 end)
      |> assign(
        :size_class,
        case assigns[:size] || "md" do
          "sm" -> "w-8 h-8"
          "md" -> "w-16 h-16"
          "lg" -> "w-32 h-32"
          _ -> "w-16 h-16"
        end
      )
      |> assign(:fill, if(assigns[:is_locked], do: "#e2e8f0", else: assigns[:color]))
      |> assign(:stroke, if(assigns[:is_locked], do: "#94a3b8", else: "#78350f"))
      |> assign(
        :path,
        case assigns[:trophy_id] do
          "t_50" ->
            # Shield/Badge
            "<path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z\" />"

          "t_100" ->
            # Medal with ribbon
            "<circle cx=\"12\" cy=\"8\" r=\"7\" /><path d=\"M8.21 13.89L7 23l5-3 5 3-1.21-9.12\" />"

          "t_200" ->
            # Ribbon badge
            "<circle cx=\"12\" cy=\"10\" r=\"5\" /><path d=\"M12 15l-3 6 3-2 3 2-3-6\" />"

          "t_300" ->
            # Trophy cup
            "<path d=\"M8 21h8\" /><path d=\"M12 12v9\" /><path d=\"M5.3 18h13.4\" /><path d=\"M6 3h12a2 2 0 0 1 2 2v2a5 5 0 0 1-4 4.9H8.1A5 5 0 0 1 4 7V5a2 2 0 0 1 2-2z\" />"

          "t_400" ->
            # Star
            "<polygon points=\"12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2\" />"

          "t_500" ->
            # Crown
            "<path d=\"M2 4l3 12h14l3-12-6 7-4-7-4 7-6-7z\" /><path d=\"M5 16h14\" />"

          "t_750" ->
            # Diamond/Gem
            "<path d=\"M6 3h12l4 6-10 10L2 9z\" />"

          "t_1000" ->
            # King's crown
            "<path d=\"M21 12.79A22.78 22.78 0 0 1 12 2a22.9 22.9 0 0 1-9 10.79L2 21h20l-1-8.21z\" />"

          _ ->
            # Default: Large elaborate cup
            "<path d=\"M10 15v4a3 3 0 0 0 6 0v-4\" /><path d=\"M10 15a6 6 0 0 1 6 0\" /><path d=\"M13 3a10 10 0 0 0-10 10v0a3 3 0 0 0 6 0V5\" /><path d=\"M13 3a10 10 0 0 1 10 10v0a3 3 0 0 1-6 0V5\" /><line x1=\"8\" y1=\"21\" x2=\"18\" y2=\"21\" />"
        end
      )

    ~H"""
    <div class={[
      "relative flex items-center justify-center transition-transform hover:scale-110",
      if(@is_locked, do: "opacity-50 grayscale", else: "opacity-100")
    ]}>
      <svg
        class={"#{@size_class} drop-shadow-md"}
        viewBox="0 0 24 24"
        fill={if @is_locked, do: "none", else: @fill}
        stroke={@stroke}
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        {Phoenix.HTML.raw(@path)}
      </svg>
      <%= if @prestige_multiplier > 1 and !@is_locked do %>
        <div class="absolute -top-2 -right-2 bg-red-500 text-white font-bold text-xs rounded-full w-6 h-6 flex items-center justify-center border-2 border-white shadow-sm animate-bounce">
          x{@prestige_multiplier}
        </div>
      <% end %>
    </div>
    """
  end
end
