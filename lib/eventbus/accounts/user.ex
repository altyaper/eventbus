defmodule Eventbus.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(superadmin)
  @username_format ~r/^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :role, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a user from a username and password.

  ## Options

    * `:hash_password` - hashes the password into `:hashed_password`.
      Defaults to `true`; pass `false` for live form validation so bcrypt
      doesn't run on every keystroke.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :password])
    |> update_change(:username, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:username, :password])
    |> validate_length(:username, min: 3, max: 32)
    |> validate_format(:username, @username_format,
      message: "must be lowercase letters, digits, '.', '-', '_'"
    )
    |> unsafe_validate_unique(:username, Eventbus.Repo)
    |> unique_constraint(:username)
    |> validate_length(:password, min: 12, max: 72)
    |> validate_confirmation(:password, message: "does not match password")
    |> maybe_hash_password(opts)
  end

  @doc false
  def role_changeset(changeset, role) when role in @roles do
    put_change(changeset, :role, role)
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
  response time doesn't reveal whether a username exists.
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
