defmodule LestrarvinurPhoenixWeb.PacmanOverlay do
  @moduledoc """
  Shared overlay component for the Pac-Man twist minigame ("Orðagleypir").
  Used by both the reading game (GameLive) and the math game (MathGameLive).
  The game itself runs client-side in Phaser via the PacmanGame JS hook; the
  server only holds the item list and the eaten counter that drives completion.
  """
  use LestrarvinurPhoenixWeb, :html

  attr :items, :list, required: true
  attr :eaten, :integer, required: true
  attr :total, :integer, required: true
  attr :prompt, :string, default: "Borðaðu öll orðin!"

  def pacman_overlay(assigns) do
    assigns = assign(assigns, :items_json, items_json(assigns.items))

    ~H"""
    <div
      id="pacman-game"
      phx-hook="PacmanGame"
      data-items={@items_json}
      data-phaser-src={~p"/vendor/phaser.min.js"}
      class="absolute inset-0 z-50 overflow-hidden"
      style="background: #0f172a;"
    >
      <button
        phx-click="skip_pacman_game"
        class="absolute top-4 right-4 z-30 bg-white/20 hover:bg-white/30 backdrop-blur rounded-full p-3 text-white transition-all"
        aria-label="Skip game"
      >
        <.icon name="hero-x-mark" class="w-6 h-6" />
      </button>

      <div class="absolute top-4 left-4 z-30 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white font-bold">
        {@eaten} / {@total}
      </div>

      <%!-- phx-update="ignore" keeps LiveView away from the Phaser-managed
           canvas when the eaten counter re-renders. --%>
      <div data-game-arena phx-update="ignore" id="pacman-arena" class="absolute inset-0"></div>

      <div class="absolute bottom-4 left-0 right-0 text-center text-white/70 text-sm pointer-events-none z-30">
        {@prompt} Strjúktu til að stýra!
      </div>
    </div>
    """
  end

  # Not intended for use outside this module
  def items_json(items) do
    items
    |> Enum.map(fn item ->
      %{id: item.id, text: item.text, category: to_string(item.category)}
    end)
    |> Jason.encode!()
  end
end
