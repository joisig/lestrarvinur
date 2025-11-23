defmodule LestrarvinurPhoenix.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :username, :string, primary_key: true
      add :total_words_read, :integer, default: 0, null: false
      add :unlocked_trophies, :text, default: "[]", null: false  # JSON array as text
      add :is_prestige, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
  end
end
