defmodule LestrarvinurPhoenixWeb.MathGameLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.{Accounts, Accounts.User, MathConstants}
  import LestrarvinurPhoenixWeb.CentipedeOverlay
  import LestrarvinurPhoenixWeb.PacmanOverlay, only: [pacman_overlay: 1]
  import LestrarvinurPhoenixWeb.InvadersOverlay, only: [invaders_overlay: 1]

  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_user(username) do
      nil ->
        {:ok, redirect(socket, to: ~p"/")}

      user ->
        level_counts = User.decode_math_level_counts(user)
        highest_level = MathConstants.highest_unlocked_level(level_counts)

        saved_sequence = User.decode_math_sequence(user)

        valid_saved? =
          saved_sequence != [] and user.math_current_index < length(saved_sequence) and
            Enum.all?(saved_sequence, fn item -> is_list(Map.get(item, "choices")) end)

        {sequence, current_index} =
          if valid_saved? do
            restored =
              Enum.map(saved_sequence, fn item ->
                %{
                  question: item["question"],
                  answer: item["answer"],
                  level: item["level"],
                  choices: item["choices"]
                }
              end)

            {restored, user.math_current_index}
          else
            new_sequence = MathConstants.generate_game_sequence(highest_level)
            encoded = User.encode_sequence(new_sequence)

            Accounts.update_user(user, %{
              math_shuffled_sequence: encoded,
              math_current_index: 0
            })

            atom_sequence =
              Enum.map(new_sequence, fn item ->
                %{
                  question: item["question"],
                  answer: item["answer"],
                  level: item["level"],
                  choices: item["choices"]
                }
              end)

            {atom_sequence, 0}
          end

        current_problem = Enum.at(sequence, current_index)

        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:level_counts, level_counts)
         |> assign(:highest_level, highest_level)
         |> assign(:sequence, sequence)
         |> assign(:current_index, current_index)
         |> assign(:current_problem, current_problem)
         |> assign(:last_wrong_index, nil)
         |> assign(:session_count, 0)
         |> assign(:show_encouragement, false)
         |> assign(:encouragement_text, "")
         |> assign(:just_unlocked, nil)
         |> assign(:trophy_multiplier, 1)
         |> assign(:level_up, nil)
         # Dragon state
         |> assign(:recent_problems, [])
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
         # Centipede state
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
        {:noreply, socket}

      socket.assigns.show_encouragement or socket.assigns.just_unlocked != nil or
          socket.assigns.level_up != nil ->
        {:noreply,
         socket
         |> assign(:show_encouragement, false)
         |> assign(:just_unlocked, nil)
         |> assign(:level_up, nil)}

      true ->
        # No-op outside modal flows: the kid advances by tapping a correct choice.
        {:noreply, socket}
    end
  end

  def handle_event("choose", %{"index" => idx_str}, socket) do
    cond do
      minigame_active?(socket) or
        socket.assigns.show_encouragement or
        socket.assigns.just_unlocked != nil or socket.assigns.level_up != nil ->
        {:noreply, socket}

      true ->
        idx = String.to_integer(idx_str)
        chosen = Enum.at(socket.assigns.current_problem.choices, idx)

        if chosen == socket.assigns.current_problem.answer do
          handle_problem_completed(socket)
        else
          Process.send_after(self(), :clear_wrong, 600)
          {:noreply, assign(socket, :last_wrong_index, idx)}
        end
    end
  end

  def handle_event("word_flung", params, socket) do
    word_id = params["word_id"]
    is_hit = params["is_hit"] == true
    hit_x = params["hit_x"] || Enum.random(20..80)
    hit_y = params["hit_y"] || Enum.random(20..80)

    visible = Enum.reject(socket.assigns.dragon_visible_words, fn w -> w.id == word_id end)
    flung_count = socket.assigns.dragon_words_flung + 1

    health =
      if is_hit do
        max(0, socket.assigns.dragon_health - 1)
      else
        socket.assigns.dragon_health
      end

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

    if is_hit do
      Process.send_after(self(), {:clear_hit, word_id}, 900)
    end

    Process.send_after(self(), :next_dragon_word, 100)

    {:noreply, socket}
  end

  def handle_event("skip_dragon_game", _params, socket) do
    socket =
      socket
      |> assign(:dragon_mode, false)
      |> assign(:dragon_words_queue, [])
      |> assign(:dragon_visible_words, [])
      |> assign(:dragon_words_flung, 0)
      |> assign(:dragon_total_words, 0)
      |> assign(:dragon_hit_active, false)

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

  def handle_info(:clear_wrong, socket) do
    {:noreply, assign(socket, :last_wrong_index, nil)}
  end

  def handle_info(:next_dragon_word, socket) do
    queue = socket.assigns.dragon_words_queue
    visible = socket.assigns.dragon_visible_words
    health = socket.assigns.dragon_health

    cond do
      health == 0 and not socket.assigns.dragon_exploding ->
        socket = assign(socket, :dragon_exploding, true)
        Process.send_after(self(), :dragon_explosion_done, 2000)
        {:noreply, socket}

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
  def handle_problem_completed(socket) do
    user = socket.assigns.user
    problem = socket.assigns.current_problem
    new_streak = socket.assigns.session_count + 1
    old_progress = rem(user.total_math_problems, MathConstants.prestige_threshold())

    # Track recent problems for dragon game
    recent = [problem | socket.assigns.recent_problems] |> Enum.take(100)

    # Increment counter and level count
    {:ok, updated_user} = Accounts.increment_math_problems(user, problem.level)
    new_progress = rem(updated_user.total_math_problems, MathConstants.prestige_threshold())
    cycle = div(updated_user.total_math_problems, MathConstants.prestige_threshold())

    # Check level unlock
    new_level_counts = User.decode_math_level_counts(updated_user)
    new_highest = MathConstants.highest_unlocked_level(new_level_counts)
    old_highest = socket.assigns.highest_level

    # Check trophy
    wrapped = new_progress < old_progress

    newly_unlocked =
      Enum.find(MathConstants.trophies(), fn trophy ->
        cond do
          wrapped -> old_progress < trophy.threshold
          true -> old_progress < trophy.threshold and new_progress >= trophy.threshold
        end
      end)

    # Dragon every 100
    dragon_milestone =
      rem(updated_user.total_math_problems, 100) == 0 and updated_user.total_math_problems > 0

    socket =
      socket
      |> assign(:user, updated_user)
      |> assign(:recent_problems, recent)
      |> assign(:level_counts, new_level_counts)
      |> assign(:highest_level, new_highest)

    # Milestone minigame: dragon (2/3) or centipede (1/3), unless the user has
    # a forced game queued up (e.g. centipede on first run after the new game
    # was added).
    socket =
      if dragon_milestone do
        {game, updated_user} = pick_and_consume_milestone_game(updated_user)
        socket = assign(socket, :user, updated_user)

        socket =
          case game do
            :dragon -> setup_dragon_mode(socket, recent)
            :centipede -> setup_centipede_mode(socket, recent)
            :pacman -> setup_pacman_mode(socket, recent)
            :invaders -> setup_invaders_mode(socket, recent)
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
        socket
        |> then(fn s ->
          # Level up notification (if not during dragon)
          if new_highest > old_highest do
            assign(s, :level_up, MathConstants.get_level(new_highest))
          else
            s
          end
        end)
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
          # Encouragement every 10 (if no trophy, no level up, no dragon)
          if newly_unlocked == nil and s.assigns.level_up == nil and rem(new_streak, 10) == 0 do
            s
            |> assign(:show_encouragement, true)
            |> assign(:encouragement_text, MathConstants.random_encouragement())
          else
            s
          end
        end)
      end

    # Advance to next problem
    next_index = socket.assigns.current_index + 1

    {next_index, sequence, final_user} =
      if next_index >= length(socket.assigns.sequence) do
        new_sequence = MathConstants.generate_game_sequence(new_highest)
        encoded = User.encode_sequence(new_sequence)

        {:ok, user_with_new} =
          Accounts.update_user(updated_user, %{
            math_shuffled_sequence: encoded,
            math_current_index: 0
          })

        atom_sequence =
          Enum.map(new_sequence, fn item ->
            %{question: item["question"], answer: item["answer"], level: item["level"]}
          end)

        {0, atom_sequence, user_with_new}
      else
        {:ok, user_with_idx} =
          Accounts.update_user(updated_user, %{math_current_index: next_index})

        {next_index, socket.assigns.sequence, user_with_idx}
      end

    {:noreply,
     socket
     |> assign(:user, final_user)
     |> assign(:session_count, new_streak)
     |> assign(:current_index, next_index)
     |> assign(:sequence, sequence)
     |> assign(:current_problem, Enum.at(sequence, next_index))
     |> assign(:last_wrong_index, nil)}
  end

  # Map math levels to color categories for dragon game card borders
  # Not intended for use outside this module
  def level_to_category(level) when level in [1, 2], do: :lime
  def level_to_category(level) when level in [3, 4], do: :cyan
  def level_to_category(level) when level in [5, 6], do: :yellow
  def level_to_category(level) when level in [7, 8], do: :blue
  def level_to_category(level) when level in [9, 10], do: :red
  def level_to_category(level) when level in [11, 12], do: :green
  def level_to_category(level) when level in [13, 14], do: :purple
  def level_to_category(level) when level in [15, 16], do: :orange
  def level_to_category(_), do: :yellow

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
  # True while any milestone minigame overlay is up; used to keep answer taps
  # from leaking through the overlays.
  def minigame_active?(socket) do
    socket.assigns.dragon_mode or socket.assigns.centipede_mode or
      socket.assigns.pacman_mode or socket.assigns.invaders_mode
  end

  # Not intended for use outside this module
  def setup_dragon_mode(socket, recent_problems) do
    dragon_items =
      recent_problems
      |> Enum.take(35)
      |> Enum.shuffle()
      |> Enum.with_index()
      |> Enum.map(fn {p, idx} ->
        %{
          id: "dw-#{idx}",
          word: "#{p.question} = #{p.answer}",
          category: level_to_category(p.level)
        }
      end)

    {initial_visible, remaining} = Enum.split(dragon_items, 6)

    socket
    |> assign(:dragon_mode, true)
    |> assign(:dragon_words_queue, remaining)
    |> assign(:dragon_visible_words, initial_visible)
    |> assign(:dragon_words_flung, 0)
    |> assign(:dragon_total_words, length(dragon_items))
    |> assign(:dragon_hit_active, false)
  end

  # Not intended for use outside this module
  def setup_centipede_mode(socket, recent_problems) do
    segments =
      recent_problems
      |> Enum.shuffle()
      |> Enum.take(25)
      |> Enum.with_index()
      |> Enum.map(fn {p, idx} ->
        %{
          id: "cs-#{idx}",
          text: "#{p.question} = #{p.answer}",
          category: level_to_category(p.level)
        }
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
    end

    socket
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
  def setup_pacman_mode(socket, recent_problems) do
    items =
      recent_problems
      |> Enum.shuffle()
      |> Enum.take(12)
      |> Enum.with_index()
      |> Enum.map(fn {p, idx} ->
        %{
          id: "pw-#{idx}",
          text: "#{p.question} = #{p.answer}",
          category: level_to_category(p.level)
        }
      end)

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
  def setup_invaders_mode(socket, recent_problems) do
    items =
      recent_problems
      |> Enum.shuffle()
      |> Enum.take(18)
      |> Enum.with_index()
      |> Enum.map(fn {p, idx} ->
        %{
          id: "iw-#{idx}",
          text: "#{p.question} = #{p.answer}",
          category: level_to_category(p.level)
        }
      end)

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

  def render(assigns) do
    level_def = MathConstants.get_level(assigns.current_problem.level)
    assigns = assign(assigns, :level_def, level_def)

    ~H"""
    <div
      phx-click="next"
      class={"h-full w-full flex flex-col relative transition-colors duration-500 ease-in-out #{level_bg_color(@current_problem.level)}"}
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
            ⭐ {@user.total_math_problems}
          </div>
          <div class="bg-white/80 backdrop-blur rounded-full px-3 py-2 font-bold shadow-sm text-slate-500 text-sm">
            Stig {@highest_level}
          </div>
        </div>
      </div>
      <!-- Main Flash Card -->
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class={"bg-white w-full max-w-sm aspect-[3/4] rounded-[3rem] shadow-2xl flex flex-col relative border-8 #{level_border_color(@current_problem.level)} transform transition-all duration-300"}>
          <!-- Level label -->
          <div class={"absolute top-6 left-0 right-0 text-center text-sm font-black tracking-widest uppercase #{level_accent_color(@current_problem.level)}"}>
            {@level_def.name}
          </div>
          <!-- The problem -->
          <div class="flex-1 flex items-center justify-center px-4 pt-12">
            <h1 class="text-5xl md:text-6xl font-black text-slate-800 text-center select-none">
              {@current_problem.question} = ?
            </h1>
          </div>
          <!-- Multiple-choice buttons -->
          <div class="grid grid-cols-2 gap-3 p-5 pb-7">
            <%= for {choice, idx} <- Enum.with_index(@current_problem.choices) do %>
              <button
                phx-click="choose"
                phx-value-index={idx}
                class={"py-5 rounded-2xl text-3xl md:text-4xl font-black shadow-md transition-all active:scale-95 select-none #{choice_button_class(idx, @last_wrong_index, @current_problem.level)}"}
              >
                {choice}
              </button>
            <% end %>
          </div>
        </div>
      </div>
      <!-- Progress Bar -->
      <div class="h-4 bg-slate-200 w-full">
        <div
          class="h-full bg-emerald-500 transition-all duration-300"
          style={"width: #{rem(@session_count, 10) * 10}%"}
        >
        </div>
      </div>
      <!-- Encouragement Overlay -->
      <%= if @show_encouragement do %>
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-6">
          <div class="bg-white rounded-3xl p-8 max-w-md w-full text-center shadow-2xl">
            <div class="text-6xl mb-4">🧮</div>
            <h2 class="text-3xl font-bold text-emerald-600 mb-4">{@encouragement_text}</h2>
            <p class="text-slate-500 mb-6">Vel gert! 10 dæmi í röð!</p>
            <div class="text-sm text-slate-400">Ýttu til að halda áfram</div>
          </div>
        </div>
      <% end %>
      <!-- Level Up Overlay -->
      <%= if @level_up do %>
        <div class="absolute inset-0 bg-emerald-500/90 backdrop-blur-md z-50 flex items-center justify-center p-6">
          <div class="bg-white rounded-3xl p-8 max-w-md w-full text-center shadow-2xl flex flex-col items-center">
            <div class="text-6xl mb-4">🎉</div>
            <h2 class="text-3xl font-black text-emerald-600 mb-2">NÝTT STIG!</h2>
            <h3 class="text-2xl font-bold text-slate-800 mb-2">Stig {@level_up.id}</h3>
            <p class="text-lg text-slate-600">{@level_up.name}</p>
            <div class="mt-8 text-sm text-slate-400 font-bold uppercase tracking-widest animate-pulse">
              Ýttu til að halda áfram
            </div>
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
                prestige_multiplier={@trophy_multiplier}
              />
            </div>
            <h3 class="text-2xl font-bold text-slate-800">{@just_unlocked.name}</h3>
            <p class="text-slate-500 mt-2">
              Þú hefur leyst {@just_unlocked.threshold} dæmi<%= if @trophy_multiplier > 1 do %>
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
        <.pacman_overlay
          items={@pacman_items}
          eaten={@pacman_eaten}
          total={@pacman_total}
          prompt="Borðaðu öll dæmin!"
        />
      <% end %>
      <!-- Space Invaders Minigame Overlay -->
      <%= if @invaders_mode do %>
        <.invaders_overlay
          items={@invaders_items}
          shot={@invaders_shot}
          total={@invaders_total}
          prompt="Skjóttu öll dæmin!"
        />
      <% end %>
      <!-- Warm the Phaser cache while the kid does problems -->
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

  # Dragon game overlay (same as GameLive)
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
      <button
        phx-click="skip_dragon_game"
        class="absolute top-4 right-4 z-20 bg-white/20 hover:bg-white/30 backdrop-blur rounded-full p-3 text-white transition-all"
        aria-label="Skip game"
      >
        <.icon name="hero-x-mark" class="w-6 h-6" />
      </button>

      <div class="absolute top-4 left-4 z-20 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white font-bold">
        {@words_flung} / {@total_words}
      </div>

      <div class="h-[60%] flex flex-col items-center justify-start pt-14 relative" id="dragon-target">
        <div class="w-48 md:w-64 mb-2">
          <div class="h-4 bg-gray-800 rounded-full overflow-hidden border-2 border-white/30 shadow-lg">
            <div
              class={"h-full transition-all duration-300 #{@health_color}"}
              style={"width: #{@health_percent}%;"}
            >
            </div>
          </div>
        </div>

        <div class="dragon-container relative flex-1 w-full flex items-center justify-center">
          <img
            src="/images/dragon.jpg"
            alt="Dragon"
            class={"max-h-full max-w-[80%] object-contain rounded-2xl shadow-2xl #{if @exploding, do: "dragon-defeated", else: "dragon-bob"}"}
          />
          <%= if @hit_active and not @exploding do %>
            <div
              class="absolute pow-burst pointer-events-none z-10"
              style={"left: #{@hit_x}%; top: #{@hit_y}%; transform: translate(-50%, -50%);"}
            >
              <.comic_burst text={@hit_text} />
            </div>
          <% end %>

          <%= if @exploding do %>
            <div class="absolute inset-0 flex items-center justify-center explosion-container">
              <.mega_explosion />
            </div>
          <% end %>
        </div>
      </div>

      <div class="h-[40%] relative flex flex-wrap items-center justify-center gap-3 px-4 pb-4 content-center">
        <%= for word <- @visible_words do %>
          <div
            id={word.id}
            data-word-id={word.id}
            class={"word-flingable bg-white rounded-2xl px-4 py-3 shadow-2xl cursor-grab active:cursor-grabbing select-none word-slide-in #{dragon_card_color(word.category)}"}
          >
            <span class="text-xl md:text-2xl font-bold text-slate-800">{word.word}</span>
          </div>
        <% end %>
      </div>

      <div class="absolute bottom-2 left-0 right-0 text-center text-white/60 text-sm">
        <%= if @exploding do %>
          Vel gert!
        <% else %>
          Dragðu dæmin upp að drekanum!
        <% end %>
      </div>
    </div>
    """
  end

  defp health_bar_color(health, max_health) do
    percent = health / max_health * 100

    cond do
      percent > 60 -> "bg-green-500"
      percent > 30 -> "bg-yellow-500"
      true -> "bg-red-500"
    end
  end

  defp mega_explosion(assigns) do
    ~H"""
    <div class="mega-explosion">
      <svg viewBox="0 0 400 400" class="w-80 h-80 md:w-96 md:h-96">
        <polygon
          points="200,20 220,100 300,60 250,130 380,150 250,180 300,250 220,220 200,300 180,220 100,250 150,180 20,150 150,130 100,60 180,100"
          fill="#FFD700"
          stroke="#FF6600"
          stroke-width="4"
          class="explosion-outer"
        />
        <polygon
          points="200,50 215,110 270,80 240,140 340,160 240,185 270,230 215,205 200,270 185,205 130,230 160,185 60,160 160,140 130,80 185,110"
          fill="#FFEC00"
          stroke="#FF8C00"
          stroke-width="3"
          class="explosion-middle"
        />
        <polygon
          points="200,80 212,120 250,100 230,145 300,160 230,175 250,210 212,195 200,240 188,195 150,210 170,175 100,160 170,145 150,100 188,120"
          fill="#FFFFFF"
          stroke="#FFD700"
          stroke-width="2"
          class="explosion-inner"
        />
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

  defp comic_burst(assigns) do
    ~H"""
    <svg viewBox="0 0 200 200" class="w-32 h-32 md:w-40 md:h-40 drop-shadow-lg">
      <polygon
        points="100,10 115,60 170,40 135,80 190,100 135,120 170,160 115,140 100,190 85,140 30,160 65,120 10,100 65,80 30,40 85,60"
        fill="#FFD700"
        stroke="#FF8C00"
        stroke-width="3"
      />
      <polygon
        points="100,30 112,65 155,50 128,82 175,100 128,118 155,150 112,135 100,170 88,135 45,150 72,118 25,100 72,82 45,50 88,65"
        fill="#FFEC00"
        stroke="#FFB800"
        stroke-width="2"
      />
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

  defp dragon_card_color(:lime), do: "border-4 border-lime-400"
  defp dragon_card_color(:cyan), do: "border-4 border-cyan-400"
  defp dragon_card_color(:yellow), do: "border-4 border-yellow-400"
  defp dragon_card_color(:blue), do: "border-4 border-blue-400"
  defp dragon_card_color(:red), do: "border-4 border-red-400"
  defp dragon_card_color(:green), do: "border-4 border-green-400"
  defp dragon_card_color(:purple), do: "border-4 border-purple-400"
  defp dragon_card_color(:orange), do: "border-4 border-orange-400"
  defp dragon_card_color(_), do: "border-4 border-yellow-400"

  # Level-based colors for the flash card background
  defp level_bg_color(level) when level in [1, 2], do: "bg-lime-50"
  defp level_bg_color(level) when level in [3, 4], do: "bg-cyan-50"
  defp level_bg_color(level) when level in [5, 6], do: "bg-amber-50"
  defp level_bg_color(level) when level in [7, 8], do: "bg-blue-50"
  defp level_bg_color(level) when level in [9, 10], do: "bg-orange-50"
  defp level_bg_color(level) when level in [11, 12], do: "bg-emerald-50"
  defp level_bg_color(level) when level in [13, 14], do: "bg-purple-50"
  defp level_bg_color(level) when level in [15, 16], do: "bg-rose-50"
  defp level_bg_color(_), do: "bg-amber-50"

  defp level_border_color(level) when level in [1, 2], do: "border-lime-200"
  defp level_border_color(level) when level in [3, 4], do: "border-cyan-200"
  defp level_border_color(level) when level in [5, 6], do: "border-amber-200"
  defp level_border_color(level) when level in [7, 8], do: "border-blue-200"
  defp level_border_color(level) when level in [9, 10], do: "border-orange-200"
  defp level_border_color(level) when level in [11, 12], do: "border-emerald-200"
  defp level_border_color(level) when level in [13, 14], do: "border-purple-200"
  defp level_border_color(level) when level in [15, 16], do: "border-rose-200"
  defp level_border_color(_), do: "border-amber-200"

  defp level_accent_color(level) when level in [1, 2], do: "text-lime-600"
  defp level_accent_color(level) when level in [3, 4], do: "text-cyan-600"
  defp level_accent_color(level) when level in [5, 6], do: "text-amber-600"
  defp level_accent_color(level) when level in [7, 8], do: "text-blue-600"
  defp level_accent_color(level) when level in [9, 10], do: "text-orange-600"
  defp level_accent_color(level) when level in [11, 12], do: "text-emerald-600"
  defp level_accent_color(level) when level in [13, 14], do: "text-purple-600"
  defp level_accent_color(level) when level in [15, 16], do: "text-rose-600"
  defp level_accent_color(_), do: "text-amber-600"

  # Per-button styling. The wrong-flash class is applied only to the choice
  # the kid just tapped if it was incorrect; everyone else gets the level-tinted
  # default look.
  defp choice_button_class(idx, idx, _level), do: "bg-red-200 text-red-800 wrong-flash"
  defp choice_button_class(_idx, _wrong, level), do: choice_default_class(level)

  defp choice_default_class(level) when level in [1, 2],
    do: "bg-lime-100 text-lime-800 hover:bg-lime-200"

  defp choice_default_class(level) when level in [3, 4],
    do: "bg-cyan-100 text-cyan-800 hover:bg-cyan-200"

  defp choice_default_class(level) when level in [5, 6],
    do: "bg-amber-100 text-amber-800 hover:bg-amber-200"

  defp choice_default_class(level) when level in [7, 8],
    do: "bg-blue-100 text-blue-800 hover:bg-blue-200"

  defp choice_default_class(level) when level in [9, 10],
    do: "bg-orange-100 text-orange-800 hover:bg-orange-200"

  defp choice_default_class(level) when level in [11, 12],
    do: "bg-emerald-100 text-emerald-800 hover:bg-emerald-200"

  defp choice_default_class(level) when level in [13, 14],
    do: "bg-purple-100 text-purple-800 hover:bg-purple-200"

  defp choice_default_class(level) when level in [15, 16],
    do: "bg-rose-100 text-rose-800 hover:bg-rose-200"

  defp choice_default_class(_), do: "bg-slate-100 text-slate-800 hover:bg-slate-200"

  # Trophy icon component (same as reading game)
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
      |> assign(:path, trophy_path(assigns[:trophy_id]))

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

  # Trophy paths — math trophies use same shapes as reading trophies
  defp trophy_path("mt_50"), do: "<path d=\"M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z\" />"

  defp trophy_path("mt_100"),
    do: "<circle cx=\"12\" cy=\"8\" r=\"7\" /><path d=\"M8.21 13.89L7 23l5-3 5 3-1.21-9.12\" />"

  defp trophy_path("mt_200"),
    do: "<circle cx=\"12\" cy=\"10\" r=\"5\" /><path d=\"M12 15l-3 6 3-2 3 2-3-6\" />"

  defp trophy_path("mt_300"),
    do:
      "<path d=\"M8 21h8\" /><path d=\"M12 12v9\" /><path d=\"M5.3 18h13.4\" /><path d=\"M6 3h12a2 2 0 0 1 2 2v2a5 5 0 0 1-4 4.9H8.1A5 5 0 0 1 4 7V5a2 2 0 0 1 2-2z\" />"

  defp trophy_path("mt_400"),
    do:
      "<polygon points=\"12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2\" />"

  defp trophy_path("mt_500"),
    do: "<path d=\"M2 4l3 12h14l3-12-6 7-4-7-4 7-6-7z\" /><path d=\"M5 16h14\" />"

  defp trophy_path("mt_750"), do: "<path d=\"M6 3h12l4 6-10 10L2 9z\" />"

  defp trophy_path("mt_1000"),
    do: "<path d=\"M21 12.79A22.78 22.78 0 0 1 12 2a22.9 22.9 0 0 1-9 10.79L2 21h20l-1-8.21z\" />"

  defp trophy_path(_),
    do:
      "<path d=\"M10 15v4a3 3 0 0 0 6 0v-4\" /><path d=\"M10 15a6 6 0 0 1 6 0\" /><path d=\"M13 3a10 10 0 0 0-10 10v0a3 3 0 0 0 6 0V5\" /><path d=\"M13 3a10 10 0 0 1 10 10v0a3 3 0 0 1-6 0V5\" /><line x1=\"8\" y1=\"21\" x2=\"18\" y2=\"21\" />"
end
