defmodule LestrarvinurPhoenixWeb.CentipedeTestLive do
  @moduledoc """
  Test page for the Centipede minigame. Visit /centipede-test to try it out.
  """
  use LestrarvinurPhoenixWeb, :live_view

  alias LestrarvinurPhoenix.Constants
  import LestrarvinurPhoenixWeb.CentipedeOverlay

  def mount(_params, _session, socket) do
    segments = build_test_segments(25)

    {:ok,
     socket
     |> assign(:segments, segments)
     |> assign(:killed, 0)
     |> assign(:total, length(segments))
     |> assign(:done, false)}
  end

  def handle_event("centipede_kill", %{"id" => _id}, socket) do
    {:noreply, register_segment_done(socket)}
  end

  def handle_event("centipede_escape", %{"id" => _id}, socket) do
    {:noreply, register_segment_done(socket)}
  end

  def handle_event("skip_centipede_game", _params, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  # Not intended for use outside this module
  def register_segment_done(socket) do
    new_killed = socket.assigns.killed + 1

    if new_killed >= socket.assigns.total do
      Process.send_after(self(), :exit_centipede, 1000)
      assign(socket, :killed, new_killed) |> assign(:done, true)
    else
      assign(socket, :killed, new_killed)
    end
  end

  def handle_info(:exit_centipede, socket) do
    {:noreply, redirect(socket, to: ~p"/")}
  end

  # Not intended for use outside this module
  # Builds a deterministic-ish set of test segments using all categories.
  def build_test_segments(count) do
    categories = [:yellow, :blue, :red, :green, :purple, :orange]

    pool =
      categories
      |> Enum.flat_map(fn cat ->
        Constants.words_by_category(cat) |> Enum.map(fn w -> {w, cat} end)
      end)
      |> Enum.shuffle()
      |> Enum.take(count)

    pool
    |> Enum.with_index()
    |> Enum.map(fn {{word, cat}, idx} ->
      %{id: "cs-#{idx}", text: word, category: cat}
    end)
  end

  def render(assigns) do
    ~H"""
    <div class="h-full w-full relative bg-emerald-50">
      <.centipede_overlay segments={@segments} killed={@killed} total={@total} />
    </div>
    """
  end
end
