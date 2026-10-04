defmodule Eventbus.ApplicationsFixtures do
  @moduledoc """
  Test helpers for creating applications via `Eventbus.Applications`.
  """

  alias Eventbus.Applications.App
  alias Eventbus.Repo

  def unique_app_slug, do: "app#{System.unique_integer([:positive])}"

  @doc """
  Creates an application owned by `attrs[:owner]`, or the test's default
  user (see `Eventbus.AccountsFixtures.default_user/0`). Inserts directly so
  unconfirmed owners can get apps too. The returned struct's `:secret` holds
  the plain secret, for building Basic auth headers.
  """
  def app_fixture(attrs \\ %{}) do
    {owner, attrs} =
      Map.pop_lazy(Map.new(attrs), :owner, &Eventbus.AccountsFixtures.default_user/0)

    secret = "ebs_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    app =
      %App{
        owner_id: owner.id,
        client_id: "ebc_#{System.unique_integer([:positive])}",
        secret_hash: :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower)
      }
      |> App.create_changeset(Enum.into(attrs, %{slug: unique_app_slug()}))
      |> Repo.insert!()

    %{app | secret: secret}
  end

  @doc """
  Returns the app with `slug`, creating it if needed.
  """
  def app_with_slug(slug) do
    Repo.get_by(App, slug: slug) || app_fixture(slug: slug)
  end
end
