defmodule Eventbus.Accounts do
  @moduledoc """
  Users and their login sessions.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Accounts.{User, UserToken}

  @doc """
  Whether any user exists yet. `false` means the instance still needs setup.
  """
  def any_users?, do: Repo.exists?(User)

  @doc """
  Creates the first user as superadmin. Fails with `{:error, :already_set_up}`
  once any user exists; the table lock makes concurrent setups safe.
  """
  def create_superadmin(attrs) do
    Repo.transaction(fn ->
      Repo.query!("LOCK TABLE users IN EXCLUSIVE MODE")

      if any_users?() do
        Repo.rollback(:already_set_up)
      end

      %User{}
      |> User.registration_changeset(attrs)
      |> User.role_changeset("superadmin")
      |> Repo.insert()
      |> case do
        {:ok, user} -> user
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Changeset for the setup form, without hashing the password.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Returns the user if the username and password are valid, otherwise `nil`.
  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: String.downcase(String.trim(username)))
    if User.valid_password?(user, password), do: user
  end

  ## Session tokens

  @doc """
  Generates a session token for the user.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Returns the user for a valid, unexpired session token, or `nil`.
  """
  def get_user_by_session_token(token) do
    token |> UserToken.verify_session_token_query() |> Repo.one()
  end

  @doc """
  Deletes the session token, ending that session.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
