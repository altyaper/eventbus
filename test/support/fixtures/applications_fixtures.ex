defmodule Eventbus.ApplicationsFixtures do
  @moduledoc """
  Test helpers for creating applications via `Eventbus.Applications`.
  """

  alias Eventbus.Applications.App
  alias Eventbus.Repo

  def unique_app_slug, do: "app#{System.unique_integer([:positive])}"

  @doc """
  Creates an application. The returned struct's `:secret` holds the plain
  secret, for building Basic auth headers.
  """
  def app_fixture(attrs \\ %{}) do
    {:ok, app} =
      attrs
      |> Enum.into(%{slug: unique_app_slug()})
      |> Eventbus.Applications.create_app()

    app
  end

  @doc """
  Returns the app with `slug`, creating it if needed.
  """
  def app_with_slug(slug) do
    Repo.get_by(App, slug: slug) || app_fixture(slug: slug)
  end
end
