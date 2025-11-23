defmodule LestrarvinurPhoenix.Repo.Migrations.AddGameProgressToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :current_word_index, :integer, default: 0
      add :shuffled_sequence, :text, default: "[]"
    end
  end
end
