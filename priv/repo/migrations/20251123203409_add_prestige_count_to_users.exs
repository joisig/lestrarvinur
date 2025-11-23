defmodule LestrarvinurPhoenix.Repo.Migrations.AddPrestigeCountToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :prestige_count, :integer, default: 0
    end
  end
end
