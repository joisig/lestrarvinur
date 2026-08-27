defmodule LestrarvinurPhoenixWeb.GameLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.{Accounts, Constants}
  import LestrarvinurPhoenixWeb.CentipedeOverlay
  import LestrarvinurPhoenixWeb.PacmanOverlay, only: [pacman_overlay: 1]
  import LestrarvinurPhoenixWeb.InvadersOverlay, only: [invaders_overlay: 1]

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
                %{
                  word: personalize_phrase(item["word"], user.username),
                  category: String.to_atom(item["category"])
                }
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
                %{
                  word: personalize_phrase(item["word"], user.username),
                  category: String.to_atom(item["category"])
                }
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
         |> assign(:dragon_health, 20)
         |> assign(:dragon_max_health, 20)
         |> assign(:dragon_exploding, false)
         |> assign(:pending_trophy, nil)
         # Centipede minigame state
         |> assign(:centipede_mode, false)
         |> assign(:centipede_segments, [])
         |> assign(:centipede_killed, 0)
         |> assign(:centipede_total, 0)
         # Pac-Man minigame state
         |> assign(:pacman_mode, false)
         |> assign(:pacman_items, [])
         |> assign(:pacman_eaten, 0)
         |> assign(:pacman_total, 0)
         # Space Invaders minigame state
         |> assign(:invaders_mode, false)
         |> assign(:invaders_items, [])
         |> assign(:invaders_shot, 0)
         |> assign(:invaders_total, 0)}
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
      minigame_active?(socket) ->
        # Don't advance during minigames, clicks should be handled by the game
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

    # Update basic state
    socket =
      socket
      |> assign(:dragon_visible_words, visible)
      |> assign(:dragon_words_flung, flung_count)
      |> assign(:dragon_health, health)

    # Only show POW effect on actual hits
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

  def handle_event("centipede_kill", %{"id" => _id}, socket) do
    {:noreply, register_centipede_done(socket)}
  end

  def handle_event("centipede_escape", %{"id" => _id}, socket) do
    {:noreply, register_centipede_done(socket)}
  end

  def handle_event("skip_centipede_game", _params, socket) do
    {:noreply, exit_centipede_mode(socket)}
  end

  def handle_event("pacman_eat", %{"id" => _id}, socket) do
    {:noreply, register_pacman_eaten(socket)}
  end

  def handle_event("skip_pacman_game", _params, socket) do
    {:noreply, exit_pacman_mode(socket)}
  end

  def handle_event("pacman_game_over", _params, socket) do
    {:noreply, exit_pacman_mode(socket)}
  end

  def handle_event("pacman_cleared", _params, socket) do
    {:noreply, exit_pacman_mode(socket)}
  end

  def handle_event("invaders_hit", %{"id" => _id}, socket) do
    {:noreply, register_invader_shot(socket)}
  end

  def handle_event("skip_invaders_game", _params, socket) do
    {:noreply, exit_invaders_mode(socket)}
  end

  def handle_event("invaders_game_over", _params, socket) do
    {:noreply, exit_invaders_mode(socket)}
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

      # Game over (out of words without defeating dragon) - exit without explosion
      queue == [] and visible == [] ->
        socket =
          socket
          |> assign(:dragon_mode, false)
          |> assign(:dragon_health, 20)
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

  def handle_info(:centipede_done, socket) do
    {:noreply, exit_centipede_mode(socket)}
  end

  def handle_info(:invaders_done, socket) do
    {:noreply, exit_invaders_mode(socket)}
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

    # If we hit a milestone, start either the dragon or centipede minigame
    # (trophy is shown afterwards via :pending_trophy).
    socket =
      if dragon_milestone do
        {game, updated_user} = pick_and_consume_milestone_game(updated_user)
        socket = assign(socket, :user, updated_user)

        socket =
          case game do
            :dragon -> setup_dragon_mode(socket, recent_words)
            :centipede -> setup_centipede_mode(socket, recent_words)
            :pacman -> setup_pacman_mode(socket, recent_words)
            :invaders -> setup_invaders_mode(socket, recent_words)
          end

        if newly_unlocked do
          multiplier = if wrapped, do: cycle, else: cycle + 1

          socket
          |> assign(:pending_trophy, newly_unlocked)
          |> assign(:trophy_multiplier, multiplier)
        else
          socket
        end
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
            %{
              word: personalize_phrase(item["word"], updated_user.username),
              category: String.to_atom(item["category"])
            }
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
  # The phrasebook contains the placeholder phrase "Ég heiti Tómas"; swap the
  # name for the logged-in kid's own so they read about themselves. Applied
  # wherever a sequence is decoded or generated, so it covers saved sequences
  # that still carry the placeholder.
  def personalize_phrase("Ég heiti Tómas", username) do
    "Ég heiti " <> String.capitalize(username)
  end

  def personalize_phrase(text, _username), do: text

  # Not intended for use outside this module
  def dragon_hit_sounds do
    ["KA-POW!", "BLAM!", "BONG!", "POW!", "THUD!", "RAT-TAT-TAT!", "BIFF!", "BONK!", "KA-RACK!"]
  end

  # Not intended for use outside this module
  # For now the milestone rotation strictly alternates between the two Phaser
  # games: whatever `next_milestone_game` holds runs now, and the other one is
  # stored for the next milestone. Legacy values ("", "dragon", "centipede")
  # map to pacman. The dragon/centipede code stays around so they can rejoin
  # the rotation later.
  def pick_and_consume_milestone_game(user) do
    game = if user.next_milestone_game == "invaders", do: :invaders, else: :pacman
    next_game = if game == :invaders, do: "pacman", else: "invaders"
    {:ok, updated} = Accounts.update_user(user, %{next_milestone_game: next_game})
    {game, updated}
  end

  # Not intended for use outside this module
  # True while any milestone minigame overlay is up; used to keep flashcard
  # taps from leaking through the overlays.
  def minigame_active?(socket) do
    socket.assigns.dragon_mode or socket.assigns.centipede_mode or
      socket.assigns.pacman_mode or socket.assigns.invaders_mode
  end

  # Not intended for use outside this module
  def setup_dragon_mode(socket, recent_words) do
    # Select the 35 longest words from recent words, then shuffle
    dragon_words =
      recent_words
      |> Enum.sort_by(fn w -> -String.length(w.word) end)
      |> Enum.take(35)
      |> Enum.shuffle()
      |> Enum.with_index()
      |> Enum.map(fn {word, idx} -> Map.put(word, :id, "dw-#{idx}") end)

    {initial_visible, remaining} = Enum.split(dragon_words, 6)

    socket
    |> assign(:dragon_mode, true)
    |> assign(:dragon_words_queue, remaining)
    |> assign(:dragon_visible_words, initial_visible)
    |> assign(:dragon_words_flung, 0)
    |> assign(:dragon_total_words, length(dragon_words))
    |> assign(:dragon_hit_active, false)
  end

  # Not intended for use outside this module
  def setup_centipede_mode(socket, recent_words) do
    segments =
      recent_words
      |> Enum.shuffle()
      |> Enum.take(25)
      |> Enum.with_index()
      |> Enum.map(fn {w, idx} ->
        %{id: "cs-#{idx}", text: w.word, category: w.category}
      end)

    socket
    |> assign(:centipede_mode, true)
    |> assign(:centipede_segments, segments)
    |> assign(:centipede_killed, 0)
    |> assign(:centipede_total, length(segments))
  end

  # Not intended for use outside this module
  def register_centipede_done(socket) do
    new_killed = socket.assigns.centipede_killed + 1
    socket = assign(socket, :centipede_killed, new_killed)

    if new_killed >= socket.assigns.centipede_total do
      Process.send_after(self(), :centipede_done, 700)
      socket
    else
      socket
    end
  end

  # Not intended for use outside this module
  def exit_centipede_mode(socket) do
    socket =
      socket
      |> assign(:centipede_mode, false)
      |> assign(:centipede_segments, [])
      |> assign(:centipede_killed, 0)
      |> assign(:centipede_total, 0)

    release_pending_trophy(socket)
  end

  # Not intended for use outside this module
  # After a minigame closes, promote any trophy queued during the milestone so
  # its modal shows. Every exit_*_mode function must end with this.
  def release_pending_trophy(socket) do
    if socket.assigns.pending_trophy do
      socket
      |> assign(:just_unlocked, socket.assigns.pending_trophy)
      |> assign(:pending_trophy, nil)
    else
      socket
    end
  end

  # Not intended for use outside this module
  # Single words only — phrases are too wide for the maze capsules.
  def setup_pacman_mode(socket, recent_words) do
    items =
      recent_words
      |> Enum.reject(fn w -> Constants.phrase?(w.word) end)
      |> Enum.shuffle()
      |> Enum.take(12)
      |> Enum.with_index()
      |> Enum.map(fn {w, idx} -> %{id: "pw-#{idx}", text: w.word, category: w.category} end)

    socket
    |> assign(:pacman_mode, true)
    |> assign(:pacman_items, items)
    |> assign(:pacman_eaten, 0)
    |> assign(:pacman_total, length(items))
  end

  # Not intended for use outside this module
  # Only advances the counter display. Completion is client-driven (the
  # "pacman_cleared" event) because the plain dots, which must also all be
  # eaten, exist only client-side.
  def register_pacman_eaten(socket) do
    if socket.assigns.pacman_mode do
      assign(socket, :pacman_eaten, socket.assigns.pacman_eaten + 1)
    else
      socket
    end
  end

  # Not intended for use outside this module
  def exit_pacman_mode(socket) do
    socket
    |> assign(:pacman_mode, false)
    |> assign(:pacman_items, [])
    |> assign(:pacman_eaten, 0)
    |> assign(:pacman_total, 0)
    |> release_pending_trophy()
  end

  # Not intended for use outside this module
  # Single words only — phrases are too wide for the invader capsules.
  def setup_invaders_mode(socket, recent_words) do
    items =
      recent_words
      |> Enum.reject(fn w -> Constants.phrase?(w.word) end)
      |> Enum.shuffle()
      |> Enum.take(18)
      |> Enum.with_index()
      |> Enum.map(fn {w, idx} -> %{id: "iw-#{idx}", text: w.word, category: w.category} end)

    socket
    |> assign(:invaders_mode, true)
    |> assign(:invaders_items, items)
    |> assign(:invaders_shot, 0)
    |> assign(:invaders_total, length(items))
  end

  # Not intended for use outside this module
  def register_invader_shot(socket) do
    if socket.assigns.invaders_mode do
      shot = socket.assigns.invaders_shot + 1

      if shot >= socket.assigns.invaders_total do
        # Give the "Vel gert!" banner a moment before closing the overlay
        Process.send_after(self(), :invaders_done, 1800)
      end

      assign(socket, :invaders_shot, shot)
    else
      socket
    end
  end

  # Not intended for use outside this module
  def exit_invaders_mode(socket) do
    socket
    |> assign(:invaders_mode, false)
    |> assign(:invaders_items, [])
    |> assign(:invaders_shot, 0)
    |> assign(:invaders_total, 0)
    |> release_pending_trophy()
  end

  # Not intended for use outside this module
  # Builds the flashcard sequence: single words in curriculum order (category
  # blocks, shuffled within each block) with phrases (2+ words, from any
  # category) interleaved so roughly one in every 4-5 cards is a phrase.
  def generate_game_sequence do
    words =
      [:yellow, :red, :green, :blue, :purple, :orange]
      |> Enum.flat_map(fn category ->
        Constants.words_by_category(category)
        |> Enum.reject(&Constants.phrase?/1)
        |> Enum.shuffle()
        |> Enum.map(fn word ->
          %{"word" => word, "category" => Atom.to_string(category)}
        end)
      end)

    phrases =
      [:yellow, :red, :green, :blue, :purple, :orange, :pink]
      |> Enum.flat_map(fn category ->
        Constants.words_by_category(category)
        |> Enum.filter(&Constants.phrase?/1)
        |> Enum.map(fn phrase ->
          %{"word" => phrase, "category" => Atom.to_string(category)}
        end)
      end)

    interleave_phrases(words, phrases)
  end

  # Not intended for use outside this module
  # Inserts a phrase after every 3-4 words. The phrase pool is drawn from a
  # shuffled queue that reshuffles when exhausted, so phrases repeat as needed
  # without back-to-back duplicates within one pass.
  def interleave_phrases(words, []), do: words

  def interleave_phrases(words, phrase_pool) do
    do_interleave(words, Enum.shuffle(phrase_pool), phrase_pool, [])
  end

  # Not intended for use outside this module
  def do_interleave([], _queue, _pool, acc), do: Enum.reverse(acc)

  def do_interleave(words, [], pool, acc) do
    do_interleave(words, Enum.shuffle(pool), pool, acc)
  end

  def do_interleave(words, [phrase | queue], pool, acc) do
    {chunk, rest} = Enum.split(words, Enum.random(3..4))
    acc = [phrase | Enum.reverse(chunk, acc)]

    case rest do
      [] -> Enum.reverse(acc)
      _ -> do_interleave(rest, queue, pool, acc)
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
          <h1 class={"#{word_font_class(@current_word.word)} font-black text-slate-800 text-center select-none px-4"}>
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
          max_health={@dragon_max_health}
          exploding={@dragon_exploding}
        />
      <% end %>
      <!-- Centipede Minigame Overlay -->
      <%= if @centipede_mode do %>
        <.centipede_overlay
          segments={@centipede_segments}
          killed={@centipede_killed}
          total={@centipede_total}
        />
      <% end %>
      <!-- Pac-Man Minigame Overlay -->
      <%= if @pacman_mode do %>
        <.pacman_overlay items={@pacman_items} eaten={@pacman_eaten} total={@pacman_total} />
      <% end %>
      <!-- Space Invaders Minigame Overlay -->
      <%= if @invaders_mode do %>
        <.invaders_overlay items={@invaders_items} shot={@invaders_shot} total={@invaders_total} />
      <% end %>
      <!-- Warm the Phaser cache while the kid does flashcards -->
      <div
        id="phaser-preload"
        phx-hook="PhaserPreload"
        data-phaser-src={~p"/vendor/phaser.min.js"}
        class="hidden"
      >
      </div>
    </div>
    """
  end

  # Dragon game overlay component
  defp dragon_game_overlay(assigns) do
    {hit_x, hit_y} = assigns.hit_pos
    health_percent = round(assigns.health / assigns.max_health * 100)

    assigns = assign(assigns, :hit_x, hit_x)
    assigns = assign(assigns, :hit_y, hit_y)
    assigns = assign(assigns, :health_percent, health_percent)
    assigns = assign(assigns, :health_color, health_bar_color(assigns.health, assigns.max_health))

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
  # Not intended for use outside this module
  # Scales the flashcard font down for longer words and phrases so they fit.
  def word_font_class(word) do
    len = String.length(word)

    cond do
      len <= 8 -> "text-7xl md:text-8xl"
      len <= 14 -> "text-5xl md:text-6xl"
      len <= 22 -> "text-4xl md:text-5xl"
      true -> "text-3xl md:text-4xl"
    end
  end

  defp word_card_color(:yellow), do: "border-4 border-yellow-400"
  defp word_card_color(:blue), do: "border-4 border-blue-400"
  defp word_card_color(:red), do: "border-4 border-red-400"
  defp word_card_color(:green), do: "border-4 border-green-400"
  defp word_card_color(:purple), do: "border-4 border-purple-400"
  defp word_card_color(:orange), do: "border-4 border-orange-400"
  defp word_card_color(:pink), do: "border-4 border-pink-400"
  defp word_card_color(_), do: "border-4 border-yellow-400"

  # Background colors for list categories
  defp bg_color(:yellow), do: "bg-yellow-50"
  defp bg_color(:blue), do: "bg-blue-50"
  defp bg_color(:red), do: "bg-red-50"
  defp bg_color(:green), do: "bg-green-50"
  defp bg_color(:purple), do: "bg-purple-50"
  defp bg_color(:orange), do: "bg-orange-50"
  defp bg_color(:pink), do: "bg-pink-50"
  defp bg_color(_), do: "bg-yellow-50"

  # Border colors
  defp border_color(:yellow), do: "border-yellow-200"
  defp border_color(:blue), do: "border-blue-200"
  defp border_color(:red), do: "border-red-200"
  defp border_color(:green), do: "border-green-200"
  defp border_color(:purple), do: "border-purple-200"
  defp border_color(:orange), do: "border-orange-200"
  defp border_color(:pink), do: "border-pink-200"
  defp border_color(_), do: "border-yellow-200"

  # Accent colors
  defp accent_color(:yellow), do: "text-yellow-600"
  defp accent_color(:blue), do: "text-blue-600"
  defp accent_color(:red), do: "text-red-600"
  defp accent_color(:green), do: "text-green-600"
  defp accent_color(:purple), do: "text-purple-600"
  defp accent_color(:orange), do: "text-orange-600"
  defp accent_color(:pink), do: "text-pink-600"
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
