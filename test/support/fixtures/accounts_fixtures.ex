defmodule Eventbus.AccountsFixtures do
  @moduledoc """
  Test helpers for creating users via the `Eventbus.Accounts` context.
  """

  alias Eventbus.Accounts.User
  alias Eventbus.Repo

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_password, do: "correct horse battery"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{email: unique_user_email(), password: valid_password()})
  end

  @doc """
  Inserts a user directly. A confirmed member by default.

  ## Options (in `attrs`)

    * `:confirmed` - `false` leaves `confirmed_at` empty.
    * `:role` - `"superadmin"` or `"member"`.
  """
  def user_fixture(attrs \\ %{}) do
    {confirmed, attrs} = Map.pop(Map.new(attrs), :confirmed, true)
    {role, attrs} = Map.pop(attrs, :role, "member")

    changeset =
      %User{accepted_terms_at: DateTime.utc_now(:second)}
      |> User.registration_changeset(valid_user_attributes(attrs))
      |> User.role_changeset(role)

    changeset = if confirmed, do: User.confirm_changeset(changeset), else: changeset
    Repo.insert!(changeset)
  end

  @doc """
  The test's default user, created on first use. Apps created without an
  explicit owner belong to it, and `register_and_log_in_user` logs it in, so
  most tests needn't thread the owner through. (Setup callbacks and the test
  body share a process, hence the process dictionary.)
  """
  def default_user do
    Process.get(:default_user) || put_default_user(user_fixture())
  end

  @doc """
  Makes `user` the test's default user.
  """
  def put_default_user(user) do
    Process.put(:default_user, user)
    user
  end
end
