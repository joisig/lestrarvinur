defmodule LestrarvinurPhoenix.Repo.Migrations.AddPasswordHashToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # Nullable to allow existing users, but new registrations will require it
      add :password_hash, :string
    end
  end
end
