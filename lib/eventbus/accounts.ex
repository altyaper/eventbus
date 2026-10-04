defmodule Eventbus.Accounts do
  @moduledoc """
  Users, their login sessions and the emailed links that confirm an
  address or reset a password.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Eventbus.{Applications, Repo}
  alias Eventbus.Accounts.{User, UserNotifier, UserToken}

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
      # Setup proves ownership with the API key, so there's nothing to confirm.
      |> User.confirm_changeset()
      |> Ecto.Changeset.put_change(:accepted_terms_at, DateTime.utc_now(:second))
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
  Signs a user up: creates an unconfirmed member and their sandbox app in
  one transaction, so nobody ends up without a sandbox. Send the
  confirmation email afterwards with `deliver_user_confirmation_instructions/2`.
  """
  def register_user(attrs) do
    Repo.transaction(fn ->
      with {:ok, user} <-
             %User{}
             |> User.signup_changeset(attrs)
             |> User.role_changeset("member")
             |> Repo.insert(),
           {:ok, _sandbox} <- Applications.create_sandbox_app(user) do
        user
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Changeset for the signup form, without hashing the password.
  """
  def change_user_signup(%User{} = user, attrs \\ %{}) do
    User.signup_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Returns the user if the email and password are valid, otherwise `nil`.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: String.trim(email))
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

  ## Email confirmation

  @doc """
  Emails the user a confirmation link built by `url_fun` from the token.

  Returns `{:ok, email}`, `{:error, :already_confirmed}`, or
  `{:error, :cooldown}` when a link went out less than a minute ago. A failed
  delivery is logged but still returns `{:ok, email}`: the user can resend,
  and signup mustn't fail because the email provider hiccuped.
  """
  def deliver_user_confirmation_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    cond do
      user.confirmed_at ->
        {:error, :already_confirmed}

      Repo.exists?(UserToken.recently_sent_query(user, "confirm")) ->
        {:error, :cooldown}

      true ->
        deliver_email_token(
          user,
          "confirm",
          url_fun,
          &UserNotifier.deliver_confirmation_instructions/2
        )
    end
  end

  @doc """
  Confirms the user behind a confirmation token and deletes their other
  confirmation tokens. Returns `{:ok, user}` or `:error` for a token that is
  invalid, expired, already used or sent to a previous email.
  """
  def confirm_user(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <-
           Ecto.Multi.new()
           |> Ecto.Multi.update(:user, User.confirm_changeset(user))
           |> Ecto.Multi.delete_all(
             :tokens,
             UserToken.by_user_and_contexts_query(user, ["confirm"])
           )
           |> Repo.transaction() do
      {:ok, user}
    else
      _invalid -> :error
    end
  end

  ## Password reset

  @doc """
  Emails a reset link to the account with this email, if there is one.
  Always returns `:ok`, so the form can't be used to discover accounts; also
  silently skips sending when a link went out less than a minute ago.
  """
  def deliver_user_reset_password_instructions(email, url_fun)
      when is_binary(email) and is_function(url_fun, 1) do
    with %User{} = user <- Repo.get_by(User, email: String.trim(email)),
         false <- Repo.exists?(UserToken.recently_sent_query(user, "reset_password")) do
      deliver_email_token(
        user,
        "reset_password",
        url_fun,
        &UserNotifier.deliver_reset_password_instructions/2
      )
    end

    :ok
  end

  @doc """
  Returns the user behind a valid reset token, or `nil`.
  """
  def get_user_by_reset_password_token(token) when is_binary(token) do
    case UserToken.verify_email_token_query(token, "reset_password") do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Changeset for the reset form, without hashing the password.
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Sets a new password from a reset link and deletes every token the user
  has: all their sessions and any other emailed link. A completed reset also
  proves they own the inbox, so it confirms the email if needed.

  Returns `{:ok, user, session_tokens}` with the deleted session tokens, so
  the caller can disconnect those sessions' live views.
  """
  def reset_user_password(%User{} = user, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> then(&if(user.confirmed_at, do: &1, else: User.confirm_changeset(&1)))

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.all(:session_tokens, UserToken.by_user_and_contexts_query(user, ["session"]))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, session_tokens: tokens}} -> {:ok, user, Enum.map(tokens, & &1.token)}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  defp deliver_email_token(user, context, url_fun, deliver_fun) do
    {encoded, user_token} = UserToken.build_email_token(user, context)
    Repo.insert!(user_token)

    case deliver_fun.(user, url_fun.(encoded)) do
      {:ok, _metadata} ->
        :ok

      {:error, reason} ->
        Logger.error("Could not send #{context} email to user #{user.id}: #{inspect(reason)}")
    end

    {:ok, user.email}
  end
end
