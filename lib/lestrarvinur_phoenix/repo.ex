defmodule LestrarvinurPhoenix.Repo do
  use Ecto.Repo,
    otp_app: :lestrarvinur_phoenix,
    adapter: Ecto.Adapters.SQLite3
end
