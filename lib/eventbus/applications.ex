defmodule Eventbus.Applications do
  @moduledoc """
  Applications and their publishing credentials.

  Secrets are 32 random bytes, so they're stored as a SHA-256 hash: a slow
  password hash like bcrypt adds nothing against brute force at that entropy
  and would slow down every publish.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Accounts.{Scope, User}
  alias Eventbus.Applications.App

  @doc """
  The scope's applications sorted by slug, each with `:topics_count` set.
  """
  def list_apps_with_topic_counts(%Scope{user: user}) do
    Repo.all(
      from a in App,
        where: a.owner_id == ^user.id,
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

  @doc """
  Gets the scope's application by slug, or `nil` when there's none or it
  belongs to someone else, so pages can't tell the two apart.
  """
  def get_owned_app(%Scope{user: user}, slug), do: Repo.get_by(App, slug: slug, owner_id: user.id)

  def change_app(%App{} = app, attrs \\ %{}), do: App.create_changeset(app, attrs)

  @doc """
  Creates an application with fresh credentials. The returned struct's
  `:secret` holds the plain secret; show it once, it can't be recovered.

  Returns `{:error, :unconfirmed}` until the user confirms their email.
  """
  def create_app(%Scope{} = scope, attrs) do
    if Scope.confirmed?(scope) do
      scope.user |> new_app() |> App.create_changeset(attrs) |> insert_app()
    else
      {:error, :unconfirmed}
    end
  end

  @doc """
  Creates a new user's sandbox app, named `sandbox-` plus random characters
  since slugs are global. Skips the confirmation check: the sandbox is what
  unconfirmed users get to try things out with.
  """
  def create_sandbox_app(%User{} = user, attempts \\ 5) do
    slug =
      "sandbox-" <> String.slice(Base.encode32(:crypto.strong_rand_bytes(4), case: :lower), 0, 6)

    changeset = user |> new_app() |> App.create_changeset(%{slug: slug})

    # A taken slug fails `unsafe_validate_unique`, or loses a race and
    # inserts nothing; `on_conflict: :nothing` keeps that race from aborting
    # the caller's transaction.
    result = insert_app(changeset, on_conflict: :nothing, conflict_target: :slug)

    if slug_taken?(result) and attempts > 1 do
      create_sandbox_app(user, attempts - 1)
    else
      result
    end
  end

  defp slug_taken?({:ok, %App{id: id}}), do: is_nil(id)
  defp slug_taken?({:error, changeset}), do: Keyword.has_key?(changeset.errors, :slug)

  defp new_app(%User{id: owner_id}) do
    %App{owner_id: owner_id, client_id: generate_client_id()}
  end

  defp insert_app(changeset, opts \\ []) do
    secret = generate_secret()

    changeset
    |> Ecto.Changeset.put_change(:secret_hash, hash_secret(secret))
    |> Repo.insert(opts)
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
  Deletes the application and, through the foreign keys, all its topics,
  allowed origins and topic revocations.
  """
  def delete_app(%App{} = app) do
    with {:ok, app} <- Repo.delete(app) do
      Eventbus.Origins.refresh_cache()
      Eventbus.TopicTokens.refresh_cache()
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
