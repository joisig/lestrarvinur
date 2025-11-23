defmodule LestrarvinurPhoenixWeb.DashboardLive do
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.{Accounts, Constants}

  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_user(username) do
      nil ->
        {:ok, redirect(socket, to: ~p"/")}

      user ->
        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:trophies, Constants.trophies())
         |> assign(:is_admin, Constants.admin?(user.username))}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, redirect(socket, to: ~p"/")}
  end

  def handle_event("play", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/game?username=#{socket.assigns.user.username}")}
  end

  def handle_event("admin", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/admin?username=#{socket.assigns.user.username}")}
  end

  def handle_event("logout", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Útskráð/ur!")
     |> redirect(to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <div class="h-full overflow-y-auto bg-slate-50 flex flex-col">
      <!-- Header -->
      <header class="bg-white shadow-sm p-4 sticky top-0 z-20">
        <div class="max-w-4xl mx-auto flex justify-between items-center">
          <div>
            <h1 class="text-2xl font-black text-sky-600">Lestrarvinur</h1>
            <p class="text-xs text-slate-400"><%= @user.username %></p>
          </div>
          <div class="flex gap-4 items-center">
            <%= if @is_admin do %>
              <button
                phx-click="admin"
                class="text-sm font-bold text-sky-500 hover:text-sky-700 border border-sky-200 px-3 py-1 rounded-full"
              >
                Stjórnborð
              </button>
            <% end %>
            <button
              phx-click="logout"
              class="text-sm font-medium text-slate-400 hover:text-red-500"
            >
              Útskrá
            </button>
          </div>
        </div>
      </header>
      <!-- Main Content -->
      <main class="flex-1 max-w-4xl mx-auto w-full p-4 pb-32">
        <!-- Stats Card -->
        <div class="bg-gradient-to-br from-sky-400 to-blue-600 rounded-3xl p-6 text-white shadow-lg mb-8 relative overflow-hidden">
          <div class="relative z-10">
            <h2 class="text-lg font-medium opacity-90">Heildarfjöldi orða</h2>
            <div class="text-6xl font-black tracking-tight my-2">
              <%= @user.total_words_read %>
            </div>
          </div>
          <!-- Decorative shapes -->
          <div class="absolute top-0 right-0 w-32 h-32 bg-white opacity-10 rounded-full -mr-10 -mt-10">
          </div>
          <div class="absolute bottom-0 left-0 w-24 h-24 bg-black opacity-10 rounded-full -ml-10 -mb-10">
          </div>
        </div>
        <!-- Action Button -->
        <div class="flex justify-center mb-10 sticky bottom-6 z-30 pointer-events-none">
          <button
            phx-click="play"
            class="pointer-events-auto bg-green-500 hover:bg-green-600 text-white font-extrabold text-2xl px-12 py-6 rounded-full shadow-xl transform transition hover:scale-105 active:scale-95 flex items-center gap-3 ring-4 ring-green-200"
          >
            <span>SPILA</span>
            <.icon name="hero-play-circle" class="h-8 w-8" />
          </button>
        </div>
        <!-- Trophy Cabinet -->
        <h3 class="text-xl font-bold text-slate-800 mb-4 px-2">Bikarasafn</h3>
        <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-4">
          <%= for trophy <- @trophies do %>
            <%
              cycle = div(@user.total_words_read, Constants.prestige_threshold())
              progress = rem(@user.total_words_read, Constants.prestige_threshold())
              is_unlocked = cycle > 0 or progress >= trophy.threshold
              multiplier = cond do
                progress >= trophy.threshold -> cycle + 1
                cycle > 0 -> cycle
                true -> 0
              end
            %>
            <div class={[
              "flex flex-col items-center justify-center p-4 rounded-2xl border-2",
              if(is_unlocked, do: "bg-white border-slate-100 shadow-sm", else: "bg-slate-100 border-slate-200")
            ]}>
              <div class="my-2">
                <.trophy_icon
                  trophy_id={trophy.id}
                  color={trophy.color}
                  is_locked={!is_unlocked}
                  prestige_multiplier={multiplier}
                  size="md"
                />
              </div>
              <div class="mt-3 text-center">
                <div class={[
                  "font-bold text-sm",
                  if(is_unlocked, do: "text-slate-800", else: "text-slate-400")
                ]}>
                  <%= trophy.name %>
                </div>
                <div class="text-xs text-slate-400 font-mono mt-1">
                  <%= trophy.threshold %> orð
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  # Trophy icon component
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
