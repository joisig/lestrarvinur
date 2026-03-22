defmodule LestrarvinurPhoenix.Repo.Migrations.AddMathGameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :total_math_problems, :integer, default: 0, null: false
      add :math_level_counts, :string, default: "{}", null: false
      add :math_current_index, :integer, default: 0, null: false
      add :math_shuffled_sequence, :string, default: "[]", null: false
    end
  end
end
