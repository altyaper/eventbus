defmodule Eventbus.Applications do
  @moduledoc """
  Applications and their publishing credentials.

  Secrets are 32 random bytes, so they're stored as a SHA-256 hash: a slow
  password hash like bcrypt adds nothing against brute force at that entropy
  and would slow down every publish.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Applications.App

  @doc """
  All applications sorted by slug, each with `:topics_count` set.
  """
  def list_apps_with_topic_counts do
    Repo.all(
      from a in App,
        left_join: t in assoc(a, :topics),
        group_by: a.id,
        order_by: a.slug,
        select: %{a | topics_count: count(t.id)}
    )
  end

  def get_app!(id), do: Repo.get!(App, id)

  @doc """
  Gets an application by slug, or `nil`.
  """
  def get_app_by_slug(slug), do: Repo.get_by(App, slug: slug)

  def change_app(%App{} = app, attrs \\ %{}), do: App.create_changeset(app, attrs)

  @doc """
  Creates an application with fresh credentials. The returned struct's
  `:secret` holds the plain secret; show it once, it can't be recovered.
  """
  def create_app(attrs) do
    secret = generate_secret()

    %App{client_id: generate_client_id(), secret_hash: hash_secret(secret)}
    |> App.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, app} -> {:ok, %{app | secret: secret}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Replaces the app's secret; the old one stops working immediately. The
  returned struct's `:secret` holds the new plain secret.
  """
  def regenerate_secret(%App{} = app) do
    secret = generate_secret()

    app
    |> Ecto.Changeset.change(secret_hash: hash_secret(secret))
    |> Repo.update()
    |> case do
      {:ok, app} -> {:ok, %{app | secret: secret}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes the application and, through the foreign keys, all its topics and
  allowed origins.
  """
  def delete_app(%App{} = app) do
    with {:ok, app} <- Repo.delete(app) do
      Eventbus.Origins.refresh_cache()
      {:ok, app}
    end
  end

  @doc """
  Returns `{:ok, app}` when the client id and secret match, `:error`
  otherwise. Always hashes and compares, so timing doesn't reveal whether the
  client id exists.
  """
  def authenticate(client_id, secret) when is_binary(client_id) and is_binary(secret) do
    app = Repo.get_by(App, client_id: client_id)
    expected = if app, do: app.secret_hash, else: hash_secret("no such client")

    if Plug.Crypto.secure_compare(hash_secret(secret), expected) and app do
      {:ok, app}
    else
      :error
    end
  end

  def authenticate(_client_id, _secret), do: :error

  defp generate_client_id, do: "ebc_" <> random_token(12)
  defp generate_secret, do: "ebs_" <> random_token(32)

  defp random_token(bytes),
    do: Base.url_encode64(:crypto.strong_rand_bytes(bytes), padding: false)

  defp hash_secret(secret), do: :crypto.hash(:sha256, secret) |> Base.encode16(case: :lower)
end
