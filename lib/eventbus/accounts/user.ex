defmodule Eventbus.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(superadmin member)
  @email_format ~r/^[^@,;\s]+@[^@,;\s]+$/

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, :string
    field :confirmed_at, :utc_datetime
    field :accepted_terms_at, :utc_datetime
    # The signup form's "I agree" checkbox; stored as `accepted_terms_at`.
    field :terms, :boolean, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a user from an email and password.

  ## Options

    * `:hash_password` - hashes the password into `:hashed_password`.
      Defaults to `true`; pass `false` for live form validation so bcrypt
      doesn't run on every keystroke.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_email()
    |> validate_password(opts)
  end

  @doc """
  Changeset for public signup: a registration that must also accept the
  terms.
  """
  def signup_changeset(user, attrs, opts \\ []) do
    user
    |> registration_changeset(attrs, opts)
    |> cast(attrs, [:terms])
    |> validate_acceptance(:terms, message: "must be accepted to sign up")
    |> put_change(:accepted_terms_at, DateTime.utc_now(:second))
  end

  @doc """
  Changeset for setting a new password, e.g. from a reset link.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_password(opts)
  end

  @doc false
  def role_changeset(changeset, role) when role in @roles do
    put_change(changeset, :role, role)
  end

  @doc """
  Marks the user's email as confirmed.
  """
  def confirm_changeset(user_or_changeset) do
    change(user_or_changeset, confirmed_at: DateTime.utc_now(:second))
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email])
    |> validate_format(:email, @email_format, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Eventbus.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    password = get_change(changeset, :password)

    if Keyword.get(opts, :hash_password, true) && password && changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies the password. Runs a dummy check when there's no user, so the
  response time doesn't reveal whether an email is registered.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
