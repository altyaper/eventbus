defmodule Eventbus.AccountsFixtures do
  @moduledoc """
  Test helpers for creating users via the `Eventbus.Accounts` context.
  """

  alias Eventbus.Accounts.User
  alias Eventbus.Repo

  def unique_username, do: "user#{System.unique_integer([:positive])}"
  def valid_password, do: "correct horse battery"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{username: unique_username(), password: valid_password()})
  end

  @doc """
  Inserts a superadmin directly, bypassing the "only the first user" rule of
  `Accounts.create_superadmin/1` so tests can create several.
  """
  def user_fixture(attrs \\ %{}) do
    %User{}
    |> User.registration_changeset(valid_user_attributes(attrs))
    |> User.role_changeset("superadmin")
    |> Repo.insert!()
  end
end
