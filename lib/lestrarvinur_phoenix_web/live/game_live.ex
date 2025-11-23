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
            Accounts.update_user(user, %{shuffled_sequence: encoded_sequence, current_word_index: 0})

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
         |> assign(:current_word, Enum.at(sequence, current_index))}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/")}
  end

  def handle_event("exit", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/dashboard?username=#{socket.assigns.user.username}")}
  end

  def handle_event("next", _params, socket) do
    if socket.assigns.show_encouragement or socket.assigns.just_unlocked do
      # Dismiss modal
      {:noreply,
       socket
       |> assign(:show_encouragement, false)
       |> assign(:just_unlocked, nil)}
    else
      handle_word_completed(socket)
    end
  end

  def handle_event("speak_word", _params, socket) do
    # Audio playback is handled client-side via JavaScript
    # We just need to provide the audio URL if available
    {:noreply, socket}
  end

  # Not intended for use outside this module
  defp handle_word_completed(socket) do
    user = socket.assigns.user
    new_streak = socket.assigns.session_count + 1
    old_progress = rem(user.total_words_read, Constants.prestige_threshold())

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

    # Update socket with new user and possibly trophy unlock
    socket =
      socket
      |> assign(:user, updated_user)
      |> then(fn s ->
        if newly_unlocked do
          # If wrapped, we're unlocking for the cycle we just completed
          # Otherwise, we're unlocking in the current cycle
          multiplier = if wrapped, do: cycle, else: cycle + 1

          s
          |> assign(:just_unlocked, newly_unlocked)
          |> assign(:trophy_multiplier, multiplier)
        else
          s
        end
      end)

    # Determine if we show encouragement (every 10 words, if no trophy unlocked)
    socket =
      if newly_unlocked == nil and rem(new_streak, 10) == 0 do
        encouragement = Constants.random_encouragement()

        socket
        |> assign(:show_encouragement, true)
        |> assign(:encouragement_text, encouragement)
      else
        socket
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
          Accounts.update_user(updated_user, %{shuffled_sequence: encoded_sequence, current_word_index: 0})

        # Convert to atom keys for LiveView
        atom_sequence =
          Enum.map(new_sequence, fn item ->
            %{word: item["word"], category: String.to_atom(item["category"])}
          end)

        {0, atom_sequence, user_with_new_sequence}
      else
        # Continue with current sequence, just update the index
        {:ok, user_with_new_index} = Accounts.update_user(updated_user, %{current_word_index: next_index})
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
  defp generate_game_sequence do
    yellow = Constants.words_by_category(:yellow)
    red = Constants.words_by_category(:red)
    green = Constants.words_by_category(:green)
    blue = Constants.words_by_category(:blue)

    (Enum.shuffle(yellow) ++
       Enum.shuffle(red) ++
       Enum.shuffle(green) ++
       Enum.shuffle(blue))
    |> Enum.map(fn word -> %{"word" => word, "category" => Atom.to_string(get_category(word))} end)
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
            ⭐ <%= @user.total_words_read %>
          </div>
        </div>
      </div>
      <!-- Main Flashcard Area -->
      <div class="flex-1 flex flex-col items-center justify-center p-6">
        <div class={"bg-white w-full max-w-sm aspect-[3/4] rounded-[3rem] shadow-2xl flex flex-col items-center justify-center relative border-8 #{border_color(@current_word.category)} transform transition-all duration-300"}>
          <!-- Word Category Label -->
          <div class={"absolute top-8 text-sm font-black tracking-widest uppercase #{accent_color(@current_word.category)}"}>
            <%= Constants.color_name(@current_word.category) %> listi
          </div>
          <!-- The Word -->
          <h1 class="text-7xl md:text-8xl font-black text-slate-800 text-center select-none">
            <%= @current_word.word %>
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
            <h2 class="text-3xl font-bold text-sky-600 mb-4"><%= @encouragement_text %></h2>
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
            <h3 class="text-2xl font-bold text-slate-800"><%= @just_unlocked.name %></h3>
            <p class="text-slate-500 mt-2">
              Þú hefur lesið <%= @just_unlocked.threshold %> orð<%= if assigns[:trophy_multiplier] && @trophy_multiplier > 1 do %> (x<%= @trophy_multiplier %>)<% end %>!
            </p>
            <div class="mt-8 text-sm text-slate-400 font-bold uppercase tracking-widest animate-pulse">
              Ýttu til að halda áfram
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

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
      |> assign(:size_class, case assigns[:size] || "md" do
        "sm" -> "w-8 h-8"
        "md" -> "w-16 h-16"
        "lg" -> "w-32 h-32"
        _ -> "w-16 h-16"
      end)
      |> assign(:fill, if(assigns[:is_locked], do: "#e2e8f0", else: assigns[:color]))
      |> assign(:stroke, if(assigns[:is_locked], do: "#94a3b8", else: "#78350f"))
      |> assign(:path, case assigns[:trophy_id] do
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
      end)

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
        <%= Phoenix.HTML.raw(@path) %>
      </svg>
      <%= if @prestige_multiplier > 1 and !@is_locked do %>
        <div class="absolute -top-2 -right-2 bg-red-500 text-white font-bold text-xs rounded-full w-6 h-6 flex items-center justify-center border-2 border-white shadow-sm animate-bounce">
          x<%= @prestige_multiplier %>
        </div>
      <% end %>
    </div>
    """
  end
end
