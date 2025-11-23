defmodule LestrarvinurPhoenix.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:username, :string, autogenerate: false}
  @derive {Phoenix.Param, key: :username}

  schema "users" do
    field :total_words_read, :integer, default: 0
    field :password_hash, :string
    field :current_word_index, :integer, default: 0
    field :shuffled_sequence, :string, default: "[]"

    # Virtual fields for password input
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :total_words_read, :current_word_index, :shuffled_sequence])
    |> validate_required([:username])
    |> validate_length(:username, min: 1, max: 255)
    |> unique_constraint(:username)
  end

  @doc """
  Changeset for user registration with password.
  """
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :password_confirmation])
    |> validate_required([:username, :password])
    |> validate_length(:username, min: 1, max: 255)
    |> validate_length(:password, min: 6, message: "Lykilorð verður að vera að minnsta kosti 6 stafir")
    |> validate_confirmation(:password, message: "Lykilorð passa ekki saman")
    |> unique_constraint(:username)
    |> hash_password()
  end

  # Not intended for use outside this module
  defp hash_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password_hash, Bcrypt.hash_pwd_salt(password))

      _ ->
        changeset
    end
  end

  @doc """
  Verifies the provided password against the stored password hash.
  """
  def valid_password?(%__MODULE__{password_hash: password_hash}, password)
      when is_binary(password_hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, password_hash)
  end

  def valid_password?(_user, _password) do
    # No password hash stored, or invalid input
    # Run a dummy verification to prevent timing attacks
    Bcrypt.verify_pass("", "$2b$12$AAAAAAAAAAAAAAAAAAAAAO0000000000000000000000000000000")
    false
  end

  # Decode JSON array of shuffled word sequence
  def decode_sequence(user) do
    case Jason.decode(user.shuffled_sequence) do
      {:ok, sequence} -> sequence
      {:error, _} -> []
    end
  end

  # Encode word sequence to JSON
  def encode_sequence(sequence) when is_list(sequence) do
    Jason.encode!(sequence)
  end
end
