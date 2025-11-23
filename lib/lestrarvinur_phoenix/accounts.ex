defmodule LestrarvinurPhoenix.Accounts do
  @moduledoc """
  The Accounts context - handles user creation, authentication, and progress tracking.
  """

  import Ecto.Query, warn: false
  alias LestrarvinurPhoenix.Repo
  alias LestrarvinurPhoenix.Accounts.User

  @doc """
  Gets a user by username.
  """
  def get_user(username) when is_binary(username) do
    Repo.get(User, username)
  end

  @doc """
  Gets a user by username, raises if not found.
  """
  def get_user!(username) when is_binary(username) do
    Repo.get!(User, username)
  end

  @doc """
  Creates a new user account with password.
  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Authenticates a user with username and password.
  Returns {:ok, user} if credentials are valid, {:error, reason} otherwise.
  """
  def authenticate_user(username, password) when is_binary(username) and is_binary(password) do
    case get_user(username) do
      nil ->
        # Run password verification even when user doesn't exist to prevent timing attacks
        Bcrypt.verify_pass("", "$2b$12$AAAAAAAAAAAAAAAAAAAAAO0000000000000000000000000000000")
        {:error, :invalid_credentials}

      user ->
        if User.valid_password?(user, password) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Updates user progress.
  """
  def update_user(user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increments total words read by 1.
  """
  def increment_words_read(user) do
    new_total = user.total_words_read + 1

    user
    |> User.changeset(%{total_words_read: new_total})
    |> Repo.update()
  end

  @doc """
  Check if username exists.
  """
  def username_exists?(username) do
    case get_user(username) do
      nil -> false
      _user -> true
    end
  end
end
