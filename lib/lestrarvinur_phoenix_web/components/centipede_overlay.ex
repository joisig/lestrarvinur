defmodule LestrarvinurPhoenixWeb.CentipedeOverlay do
  @moduledoc """
  Shared overlay component for the centipede minigame. Used by both the
  reading game (GameLive) and the math game (MathGameLive). The actual game
  loop runs client-side via the Centipede JS hook in app.js — the server only
  holds the segment list and the kill/escape counters that drive completion.
  """
  use Phoenix.Component
  import LestrarvinurPhoenixWeb.CoreComponents, only: [icon: 1]

  attr :segments, :list, required: true
  attr :killed, :integer, required: true
  attr :total, :integer, required: true

  def centipede_overlay(assigns) do
    ~H"""
    <div
      id="centipede-game"
      phx-hook="Centipede"
      class="absolute inset-0 z-50 flex flex-col overflow-hidden"
      style="background: radial-gradient(circle at 30% 20%, #84cc16 0%, #16a34a 50%, #064e3b 100%);"
    >
      <button
        phx-click="skip_centipede_game"
        class="absolute top-4 right-4 z-30 bg-white/20 hover:bg-white/30 backdrop-blur rounded-full p-3 text-white transition-all"
        aria-label="Skip game"
      >
        <.icon name="hero-x-mark" class="w-6 h-6" />
      </button>

      <div class="absolute top-4 left-4 z-30 bg-white/20 backdrop-blur rounded-full px-4 py-2 text-white font-bold">
        {@killed} / {@total}
      </div>

      <%!-- phx-update="ignore" keeps LiveView from resetting JS-managed inline
           styles (transform, opacity) when the kill counter re-renders. --%>
      <div
        data-centipede-arena
        phx-update="ignore"
        id="centipede-arena"
        class="absolute inset-0 overflow-hidden"
      >
        <%= for seg <- @segments do %>
          <div id={seg.id} class="centipede-segment" data-segment-id={seg.id}>
            <div class={"centipede-segment-inner rounded-full px-4 py-2 shadow-lg select-none cursor-pointer text-base md:text-lg font-bold whitespace-nowrap #{seg_class(seg.category)}"}>
              {seg.text}
            </div>
          </div>
        <% end %>
      </div>

      <div class="absolute bottom-4 left-0 right-0 text-center text-white/70 text-sm pointer-events-none">
        Smelltu á alla maðkana!
      </div>
    </div>
    """
  end

  defp seg_class(:lime), do: "bg-lime-200 text-lime-900 ring-2 ring-lime-400"
  defp seg_class(:cyan), do: "bg-cyan-200 text-cyan-900 ring-2 ring-cyan-400"
  defp seg_class(:yellow), do: "bg-yellow-200 text-yellow-900 ring-2 ring-yellow-400"
  defp seg_class(:blue), do: "bg-blue-200 text-blue-900 ring-2 ring-blue-400"
  defp seg_class(:red), do: "bg-red-200 text-red-900 ring-2 ring-red-400"
  defp seg_class(:green), do: "bg-emerald-200 text-emerald-900 ring-2 ring-emerald-400"
  defp seg_class(:purple), do: "bg-purple-200 text-purple-900 ring-2 ring-purple-400"
  defp seg_class(:orange), do: "bg-orange-200 text-orange-900 ring-2 ring-orange-400"
  defp seg_class(_), do: "bg-yellow-200 text-yellow-900 ring-2 ring-yellow-400"
end
