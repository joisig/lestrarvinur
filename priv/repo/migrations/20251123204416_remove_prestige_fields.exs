defmodule LestrarvinurPhoenix.Repo.Migrations.RemovePrestigeFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :is_prestige
      remove :prestige_count
      remove :unlocked_trophies
    end
  end
end
