defmodule LestrarvinurPhoenixWeb.PacmanTestLive do
  @moduledoc """
  Test page for the Pac-Man minigame. Visit /pacman-test to try it with
  random words, or /pacman-test?mode=math for random math problems.
  """
  use LestrarvinurPhoenixWeb, :live_view

  import LestrarvinurPhoenixWeb.PacmanOverlay
  alias LestrarvinurPhoenixWeb.MinigameTestItems

  def mount(params, _session, socket) do
    items = MinigameTestItems.build(params["mode"], 12, "pw")

    {:ok,
     socket
     |> assign(:items, items)
     |> assign(:eaten, 0)
     |> assign(:total, length(items))
     |> assign(:prompt, MinigameTestItems.prompt(params["mode"], "Borðaðu"))}
  end

  def handle_event("pacman_eat", %{"id" => _id}, socket) do
    {:noreply, assign(socket, :eaten, socket.assigns.eaten + 1)}
  end

  def handle_event("pacman_cleared", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def handle_event("skip_pacman_game", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def handle_event("pacman_game_over", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <div class="h-full w-full relative bg-slate-900">
      <.pacman_overlay items={@items} eaten={@eaten} total={@total} prompt={@prompt} />
    </div>
    """
  end
end
