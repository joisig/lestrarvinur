defmodule LestrarvinurPhoenixWeb.AdminLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.{Accounts, Constants, Media}

  def mount(%{"username" => username}, _session, socket) do
    # Verify admin access
    if Constants.admin?(username) do
      case Accounts.get_user(username) do
        nil ->
          {:ok, redirect(socket, to: ~p"/")}

        user ->
          word_lists = %{
            yellow: Constants.words_by_category(:yellow),
            blue: Constants.words_by_category(:blue),
            red: Constants.words_by_category(:red),
            green: Constants.words_by_category(:green)
          }

          all_words = Enum.flat_map(word_lists, fn {_category, words} -> words end)
          encouragements = Constants.encouragements()

          {:ok,
           socket
           |> assign(:user, user)
           |> assign(:word_lists, word_lists)
           |> assign(:encouragements, encouragements)
           |> assign(:words_with_audio, build_words_audio_map(all_words))
           |> assign(:encouragements_with_audio, build_encouragements_audio_map(encouragements))
           |> assign(:recording_word, nil)
           |> assign(:recording_encouragement, nil)
           |> assign(:recording_active, false)}
      end
    else
      {:ok, redirect(socket, to: ~p"/dashboard?username=#{username}")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/")}
  end

  def handle_event("back", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/dashboard?username=#{socket.assigns.user.username}")}
  end

  def handle_event("start_recording_word", %{"word" => word}, socket) do
    {:noreply,
     socket
     |> assign(:recording_word, word)
     |> assign(:recording_encouragement, nil)
     |> assign(:recording_active, true)
     |> push_event("start-recording", %{target: "word-recorder-#{word}"})}
  end

  def handle_event("start_recording_encouragement", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)

    {:noreply,
     socket
     |> assign(:recording_word, nil)
     |> assign(:recording_encouragement, index)
     |> assign(:recording_active, true)
     |> push_event("start-recording", %{target: "encouragement-recorder-#{index}"})}
  end

  def handle_event("stop_recording", _params, socket) do
    {:noreply,
     socket
     |> assign(:recording_active, false)
     |> push_event("stop-recording", %{})}
  end

  def handle_event("save-recording", %{"audio_data" => audio_data, "extension" => ext}, socket) do
    binary = Base.decode64!(audio_data)

    cond do
      socket.assigns.recording_word ->
        word = socket.assigns.recording_word

        case Media.save_word_audio(word, binary, ext) do
          {:ok, _url} ->
            audio_url = Media.get_word_audio_url(word)

            {:noreply,
             socket
             |> assign(:recording_word, nil)
             |> assign(:recording_active, false)
             |> update(:words_with_audio, fn map -> Map.put(map, word, true) end)
             |> push_event("play-saved-audio", %{url: audio_url})
             |> put_flash(:info, "Upptaka fyrir \"#{word}\" vistuð!")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:recording_word, nil)
             |> assign(:recording_active, false)
             |> put_flash(:error, "Villa við að vista upptöku")}
        end

      socket.assigns.recording_encouragement != nil ->
        index = socket.assigns.recording_encouragement
        encouragement = Enum.at(Constants.encouragements(), index)

        case Media.save_encouragement_audio(index, binary, ext) do
          {:ok, _url} ->
            audio_url = Media.get_encouragement_audio_url(index)

            {:noreply,
             socket
             |> assign(:recording_encouragement, nil)
             |> assign(:recording_active, false)
             |> update(:encouragements_with_audio, fn map -> Map.put(map, index, true) end)
             |> push_event("play-saved-audio", %{url: audio_url})
             |> put_flash(:info, "Upptaka fyrir \"#{encouragement}\" vistuð!")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:recording_encouragement, nil)
             |> assign(:recording_active, false)
             |> put_flash(:error, "Villa við að vista upptöku")}
        end

      true ->
        {:noreply,
         socket
         |> assign(:recording_active, false)
         |> put_flash(:error, "Villa: Engin upptaka í gangi")}
    end
  end

  def handle_event("recording-started", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("recording-error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:recording_active, false)
     |> assign(:recording_word, nil)
     |> assign(:recording_encouragement, nil)
     |> put_flash(:error, "Villa við að opna hljóðnema: #{error}")}
  end

  def handle_event("delete_word_audio", %{"word" => word}, socket) do
    Media.delete_word_audio(word)

    {:noreply,
     socket
     |> update(:words_with_audio, fn map -> Map.put(map, word, false) end)
     |> put_flash(:info, "Upptaka fyrir \"#{word}\" eytt")}
  end

  def handle_event("delete_encouragement_audio", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    Media.delete_encouragement_audio(index)
    encouragement = Enum.at(Constants.encouragements(), index)

    {:noreply,
     socket
     |> update(:encouragements_with_audio, fn map -> Map.put(map, index, false) end)
     |> put_flash(:info, "Upptaka fyrir \"#{encouragement}\" eytt")}
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-100 p-4 pb-20 overflow-y-auto" phx-hook="AudioRecorder" id="audio-recorder">
      <div class="max-w-4xl mx-auto bg-white rounded-3xl shadow-xl p-6">
        <div class="flex justify-between items-center mb-6">
          <h1 class="text-2xl font-bold text-slate-800">Upptökustjórnborð (Admin)</h1>
          <button phx-click="back" class="text-slate-500 hover:text-slate-700 font-bold">
            Til baka
          </button>
        </div>

        <p class="mb-6 text-slate-500 text-sm">
          Hér getur þú hlaðið upp hljóðskrám fyrir orð og hvatningarskilaboð. Smelltu á "Velja skrá" og veldu hljóðskrá til að hlaða upp.
        </p>
        <!-- Words Section -->
        <div class="mb-10">
          <h2 class="text-xl font-bold text-slate-700 mb-4">Orð</h2>

          <div class="space-y-8">
            <%= for {category, words} <- @word_lists do %>
              <div class={[
                "border-l-4 p-4 rounded-r-xl",
                category_colors(category)
              ]}>
                <h3 class="text-xl font-bold mb-4 uppercase text-slate-700">
                  <%= Constants.color_name(category) %> listi
                </h3>
                <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
                  <%= for word <- words do %>
                    <div class="flex items-center justify-between bg-white p-3 rounded-lg shadow-sm border border-slate-100">
                      <span class="font-bold text-lg text-slate-700"><%= word %></span>

                      <div class="flex gap-2">
                        <%= if @words_with_audio[word] do %>
                          <!-- Play Button -->
                          <button
                            class="p-2 bg-green-100 text-green-600 rounded-full hover:bg-green-200"
                            phx-click={
                              JS.dispatch("play-audio",
                                detail: %{url: Media.get_word_audio_url(word)}
                              )
                            }
                            title="Hlusta"
                          >
                            <.icon name="hero-play-circle" class="h-5 w-5" />
                          </button>
                          <!-- Delete Button -->
                          <button
                            phx-click="delete_word_audio"
                            phx-value-word={word}
                            class="p-2 bg-red-100 text-red-600 rounded-full hover:bg-red-200"
                            title="Eyða"
                          >
                            <.icon name="hero-trash" class="h-5 w-5" />
                          </button>
                        <% end %>

                        <%= if @recording_word == word && @recording_active do %>
                          <!-- Stop Recording Button -->
                          <button
                            phx-click="stop_recording"
                            class="p-2 bg-red-500 text-white rounded-full hover:bg-red-600 animate-pulse"
                            title="Stöðva upptöku"
                          >
                            <.icon name="hero-stop-circle" class="h-5 w-5" />
                          </button>
                        <% else %>
                          <!-- Record Button -->
                          <button
                            phx-click="start_recording_word"
                            phx-value-word={word}
                            class="p-2 bg-sky-100 text-sky-600 rounded-full hover:bg-sky-200"
                            title="Taka upp"
                          >
                            <.icon name="hero-microphone" class="h-5 w-5" />
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
        <!-- Encouragements Section -->
        <div>
          <h2 class="text-xl font-bold text-slate-700 mb-4">Hvatningarskilaboð</h2>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <%= for {encouragement, index} <- Enum.with_index(@encouragements) do %>
              <div class="flex items-center justify-between bg-white p-3 rounded-lg shadow-sm border border-slate-100">
                <div class="flex-1">
                  <span class="font-bold text-sm text-slate-700"><%= encouragement %></span>
                  <span class="text-xs text-slate-400 ml-2">#<%= index %></span>
                </div>

                <div class="flex gap-2">
                  <%= if @encouragements_with_audio[index] do %>
                    <!-- Play Button -->
                    <button
                      class="p-2 bg-green-100 text-green-600 rounded-full hover:bg-green-200"
                      phx-click={
                        JS.dispatch("play-audio",
                          detail: %{url: Media.get_encouragement_audio_url(index)}
                        )
                      }
                      title="Hlusta"
                    >
                      <.icon name="hero-play-circle" class="h-5 w-5" />
                    </button>
                    <!-- Delete Button -->
                    <button
                      phx-click="delete_encouragement_audio"
                      phx-value-index={index}
                      class="p-2 bg-red-100 text-red-600 rounded-full hover:bg-red-200"
                      title="Eyða"
                    >
                      <.icon name="hero-trash" class="h-5 w-5" />
                    </button>
                  <% end %>

                  <%= if @recording_encouragement == index && @recording_active do %>
                    <!-- Stop Recording Button -->
                    <button
                      phx-click="stop_recording"
                      class="p-2 bg-red-500 text-white rounded-full hover:bg-red-600 animate-pulse"
                      title="Stöðva upptöku"
                    >
                      <.icon name="hero-stop-circle" class="h-5 w-5" />
                    </button>
                  <% else %>
                    <!-- Record Button -->
                    <button
                      phx-click="start_recording_encouragement"
                      phx-value-index={index}
                      class="p-2 bg-sky-100 text-sky-600 rounded-full hover:bg-sky-200"
                      title="Taka upp"
                    >
                      <.icon name="hero-microphone" class="h-5 w-5" />
                    </button>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp category_colors(:yellow), do: "border-yellow-400 bg-yellow-50"
  defp category_colors(:blue), do: "border-blue-400 bg-blue-50"
  defp category_colors(:red), do: "border-red-400 bg-red-50"
  defp category_colors(:green), do: "border-green-400 bg-green-50"

  # Not intended for use outside this module
  defp build_words_audio_map(words) do
    Enum.reduce(words, %{}, fn word, acc ->
      Map.put(acc, word, Media.word_audio_exists?(word))
    end)
  end

  # Not intended for use outside this module
  defp build_encouragements_audio_map(encouragements) do
    encouragements
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {_encouragement, index}, acc ->
      Map.put(acc, index, Media.encouragement_audio_exists?(index))
    end)
  end
end
