defmodule LestrarvinurPhoenix.Repo.Migrations.QueuePacmanAsNextMilestoneGame do
  use Ecto.Migration

  # Make every existing kid see the new Pac-Man minigame at their next
  # milestone (the Space Invaders game arrives via the random rotation).
  def up do
    execute "UPDATE users SET next_milestone_game = 'pacman'"
  end

  def down do
    execute "UPDATE users SET next_milestone_game = ''"
  end
end
