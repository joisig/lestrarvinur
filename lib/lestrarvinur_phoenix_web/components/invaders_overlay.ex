defmodule LestrarvinurPhoenixWeb.InvadersOverlay do
  @moduledoc """
  Shared overlay component for the Space Invaders twist minigame ("Geimorð").
  Used by both the reading game (GameLive) and the math game (MathGameLive).
  The game itself runs client-side in Phaser via the InvadersGame JS hook; the
  server only holds the item list and the shot counter that drives completion.
  """
  use LestrarvinurPhoenixWeb, :html

  import LestrarvinurPhoenixWeb.PacmanOverlay, only: [items_json: 1]

  attr :items, :list, required: true
  attr :shot, :integer, required: true
  attr :total, :integer, required: true
  attr :prompt, :string, default: "Skjóttu öll orðin!"

  def invaders_overlay(assigns) do
    assigns = assign(assigns, :items_json, items_json(assigns.items))

    ~H"""
    <div
      id="invaders-game"
      phx-hook="InvadersGame"
      data-items={@items_json}
      data-phaser-src={~p"/vendor/phaser.min.js"}
      class="absolute inset-0 z-50 overflow-hidden"
      style="background: #020617;"
    >
      <button
        phx-click="skip_invaders_game"
        class="absolute top-4 right-4 z-30 bg-white/20 hover:bg-white/30 backdrop-blur rounded-full p-3 text-white transition-all"
        aria-label="Skip game"
      >
        <.icon name="hero-x-mark" class="w-6 h-6" />
      </button>

      <div class="absolute top-4 left-4 z-30 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white font-bold">
        {@shot} / {@total}
      </div>

      <%!-- phx-update="ignore" keeps LiveView away from the Phaser-managed
           canvas when the shot counter re-renders. The start button lives in
           here too so LiveView cannot resurrect it after JS hides it; the
           game boots paused and its click unlocks audio (iOS only counts a
           clean tap, not a drag) and starts play. --%>
      <div data-game-arena phx-update="ignore" id="invaders-arena" class="absolute inset-0">
        <div class="absolute inset-0 z-20 flex items-center justify-center pointer-events-none">
          <button
            data-game-start
            class="pointer-events-auto bg-sky-400 text-sky-950 text-5xl font-black rounded-full px-16 py-8 shadow-2xl active:scale-95 transition-transform"
          >
            ▶ Byrja!
          </button>
        </div>
      </div>

      <div class="absolute bottom-4 left-0 right-0 text-center text-white/70 text-sm pointer-events-none z-30">
        {@prompt} Dragðu til að stýra geimskipinu!
      </div>
    </div>
    """
  end
end
