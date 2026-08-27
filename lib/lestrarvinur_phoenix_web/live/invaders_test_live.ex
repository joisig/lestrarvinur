defmodule LestrarvinurPhoenixWeb.InvadersTestLive do
  @moduledoc """
  Test page for the Space Invaders minigame. Visit /invaders-test to try it
  with random words, or /invaders-test?mode=math for random math problems.
  """
  use LestrarvinurPhoenixWeb, :live_view

  import LestrarvinurPhoenixWeb.InvadersOverlay
  alias LestrarvinurPhoenixWeb.MinigameTestItems

  def mount(params, _session, socket) do
    items = MinigameTestItems.build(params["mode"], 18, "iw")

    {:ok,
     socket
     |> assign(:items, items)
     |> assign(:shot, 0)
     |> assign(:total, length(items))
     |> assign(:prompt, MinigameTestItems.prompt(params["mode"], "Skjóttu"))}
  end

  def handle_event("invaders_hit", %{"id" => _id}, socket) do
    shot = socket.assigns.shot + 1

    if shot >= socket.assigns.total do
      Process.send_after(self(), :exit_game, 2000)
    end

    {:noreply, assign(socket, :shot, shot)}
  end

  def handle_event("skip_invaders_game", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def handle_event("invaders_game_over", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def handle_info(:exit_game, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  def render(assigns) do
    ~H"""
    <div class="h-full w-full relative bg-slate-950">
      <.invaders_overlay items={@items} shot={@shot} total={@total} prompt={@prompt} />
    </div>
    """
  end
end
