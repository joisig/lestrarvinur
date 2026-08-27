defmodule LestrarvinurPhoenixWeb.MinigameMilestoneTest do
  use LestrarvinurPhoenixWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LestrarvinurPhoenix.Accounts

  # Not part of public API
  # Creates a user positioned one item away from a 100-item milestone, with
  # `next_milestone_game` forced so the test deterministically gets `game`.
  def milestone_user(game, attrs) do
    username = "kid-#{game}-#{System.unique_integer([:positive])}"

    {:ok, user} =
      Accounts.create_user(%{
        username: username,
        password: "leyndo",
        password_confirmation: "leyndo"
      })

    {:ok, user} = Accounts.update_user(user, Map.put(attrs, :next_milestone_game, game))
    user
  end

  describe "reading game milestones" do
    test "100th word starts the forced pacman game and clearing the maze ends it", %{conn: conn} do
      user = milestone_user("pacman", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")

      html = render_click(view, "next", %{})
      assert html =~ "pacman-game"

      # Eating words only advances the counter; the client decides completion
      # (every word AND every dot) via pacman_cleared.
      html = render_hook(view, "pacman_eat", %{"id" => "pw-0"})
      assert html =~ "1 / 1"
      assert html =~ "pacman-game"

      html = render_hook(view, "pacman_cleared", %{})
      refute html =~ "pacman-game"
    end

    test "100th word starts the forced invaders game and skip exits it", %{conn: conn} do
      user = milestone_user("invaders", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")

      html = render_click(view, "next", %{})
      assert html =~ "invaders-game"

      html = render_click(view, "skip_invaders_game", %{})
      refute html =~ "invaders-game"
    end

    test "game over from the client exits the pacman overlay", %{conn: conn} do
      user = milestone_user("pacman", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")
      assert render_click(view, "next", %{}) =~ "pacman-game"

      html = render_hook(view, "pacman_game_over", %{})
      refute html =~ "pacman-game"
    end

    test "game over from the client exits the invaders overlay", %{conn: conn} do
      user = milestone_user("invaders", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")
      assert render_click(view, "next", %{}) =~ "invaders-game"

      html = render_hook(view, "invaders_game_over", %{})
      refute html =~ "invaders-game"
    end

    test "milestones alternate between pacman and invaders", %{conn: conn} do
      user = milestone_user("pacman", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")
      assert render_click(view, "next", %{}) =~ "pacman-game"
      assert Accounts.get_user(user.username).next_milestone_game == "invaders"

      user = milestone_user("invaders", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")
      assert render_click(view, "next", %{}) =~ "invaders-game"
      assert Accounts.get_user(user.username).next_milestone_game == "pacman"
    end

    test "legacy next_milestone_game values map to pacman", %{conn: conn} do
      user = milestone_user("centipede", %{total_words_read: 99})

      {:ok, view, _html} = live(conn, ~p"/game?username=#{user.username}")
      assert render_click(view, "next", %{}) =~ "pacman-game"
      assert Accounts.get_user(user.username).next_milestone_game == "invaders"
    end
  end

  describe "math game milestones" do
    test "100th problem starts the forced invaders game", %{conn: conn} do
      user = milestone_user("invaders", %{total_math_problems: 99})

      {:ok, view, _html} = live(conn, ~p"/math-game?username=#{user.username}")

      html = answer_correctly(view)
      assert html =~ "invaders-game"

      html = render_hook(view, "invaders_hit", %{"id" => "iw-0"})
      assert html =~ "1 / 1"

      send(view.pid, :invaders_done)
      refute render(view) =~ "invaders-game"
    end

    test "100th problem starts the forced pacman game", %{conn: conn} do
      user = milestone_user("pacman", %{total_math_problems: 99})

      {:ok, view, _html} = live(conn, ~p"/math-game?username=#{user.username}")

      html = answer_correctly(view)
      assert html =~ "pacman-game"

      html = render_click(view, "skip_pacman_game", %{})
      refute html =~ "pacman-game"
    end
  end

  # Not part of public API
  # Taps the correct multiple-choice answer for the current problem by reading
  # the LiveView's state directly.
  def answer_correctly(view) do
    %{socket: socket} = :sys.get_state(view.pid)
    problem = socket.assigns.current_problem
    index = Enum.find_index(problem.choices, fn choice -> choice == problem.answer end)
    render_click(view, "choose", %{"index" => to_string(index)})
  end
end
