defmodule LestrarvinurPhoenix.Repo.Migrations.AddNextMilestoneGameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :next_milestone_game, :string, default: "centipede", null: false
    end
  end
end
