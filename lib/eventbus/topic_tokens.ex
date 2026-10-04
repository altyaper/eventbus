defmodule Eventbus.TopicTokens do
  @moduledoc """
  Short-lived tokens that let a browser listen to an app's topics. The app's
  backend mints one with its credentials, listing the topics (see
  `Eventbus.TopicTokens.Grant`) its user may join; the browser passes it in
  the `topic:` join params. Unlike chat tokens they don't create a user in
  eventbus: `user_id` is the app's own id, used only for revocation.

  An app with `require_topic_tokens` refuses joins without a token. Other
  apps' topics stay open to anonymous listeners, and honour tokens too.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.TopicTokens.{Grant, Revocation}

  @salt "topic grants"
  @max_ttl 3600
  @default_ttl 900
  @max_grants 100
  @cache {__MODULE__, :required_slugs}

  @mint_types %{user_id: :string, grants: {:array, :string}, ttl: :integer}

  @doc """
  Validates `attrs` (`user_id`, `grants`, optional `ttl` in seconds) and
  returns `{:ok, %{token, expires_at}}` or `{:error, changeset}`.
  """
  def mint(%App{} = app, attrs) do
    changeset =
      {%{ttl: @default_ttl}, @mint_types}
      |> Ecto.Changeset.cast(attrs, Map.keys(@mint_types))
      |> Ecto.Changeset.validate_required([:user_id, :grants])
      |> Ecto.Changeset.validate_length(:user_id, min: 1, max: 255)
      |> Ecto.Changeset.validate_length(:grants, min: 1, max: @max_grants)
      |> validate_grants(app)
      |> Ecto.Changeset.validate_number(:ttl,
        greater_than_or_equal_to: 1,
        less_than_or_equal_to: @max_ttl
      )

    with {:ok, %{user_id: user_id, grants: grants, ttl: ttl}} <-
           Ecto.Changeset.apply_action(changeset, :insert) do
      now = System.system_time(:microsecond)
      exp = now + ttl * 1_000_000

      claims = %{app: app.id, sub: user_id, grants: Enum.uniq(grants), iat: now, exp: exp}
      token = Phoenix.Token.sign(EventbusWeb.Endpoint, @salt, claims)
      {:ok, %{token: token, expires_at: DateTime.from_unix!(exp, :microsecond)}}
    end
  end

  defp validate_grants(changeset, app) do
    Ecto.Changeset.validate_change(changeset, :grants, fn :grants, grants ->
      case Enum.reject(grants, &Grant.valid?(app.slug, &1)) do
        [] ->
          []

        bad ->
          [
            grants:
              "must be topic names or name.* patterns under #{app.slug}.: #{Enum.join(bad, ", ")}"
          ]
      end
    end)
  end

  @doc """
  Verifies a token for joining `topic_name`. Returns `{:ok, claims}` when it's
  valid, unexpired, not revoked, its app still exists and one of its grants
  matches; otherwise `{:error, reason}` with reason `:expired`, `:revoked`,
  `:forbidden` (no matching grant) or `:invalid`.
  """
  def verify(token, topic_name) when is_binary(token) do
    with {:ok, claims} <- decode(token),
         :ok <- check_expiry(claims),
         %App{} <- Repo.get(App, claims.app) || {:error, :invalid},
         :ok <- check_revocation(claims),
         true <- Enum.any?(claims.grants, &Grant.matches?(&1, topic_name)) || {:error, :forbidden} do
      {:ok, claims}
    end
  end

  def verify(_token, _topic_name), do: {:error, :invalid}

  defp decode(token) do
    case Phoenix.Token.verify(EventbusWeb.Endpoint, @salt, token, max_age: @max_ttl) do
      {:ok, %{app: _, sub: _, grants: _, iat: _, exp: _} = claims} -> {:ok, claims}
      {:error, :expired} -> {:error, :expired}
      _invalid -> {:error, :invalid}
    end
  end

  defp check_expiry(%{exp: exp}) do
    if System.system_time(:microsecond) < exp, do: :ok, else: {:error, :expired}
  end

  defp check_revocation(%{app: app_id, sub: user_id, iat: iat}) do
    revoked_at =
      Repo.one(
        from r in Revocation,
          where: r.application_id == ^app_id and r.user_id == ^user_id,
          select: r.revoked_at
      )

    # `<=` so a token minted in the same microsecond as the revocation loses.
    if revoked_at && iat <= DateTime.to_unix(revoked_at, :microsecond),
      do: {:error, :revoked},
      else: :ok
  end

  @doc """
  Revokes `user_id`'s access to `app`'s topics. With `grants`, their joined
  channels whose topic matches one of the patterns are closed; tokens stay
  valid, so the app must stop granting those topics. Without, every one of
  their channels is closed and tokens minted before now are refused.
  """
  def revoke(app, user_id, grants \\ nil)

  def revoke(%App{} = app, user_id, nil) when is_binary(user_id) and user_id != "" do
    # Same clock as a token's `iat`: DateTime.utc_now/0 reads the OS clock,
    # which can be microseconds apart from System.system_time/1.
    revoked_at = DateTime.from_unix!(System.system_time(:microsecond), :microsecond)

    Repo.insert!(
      %Revocation{application_id: app.id, user_id: user_id, revoked_at: revoked_at},
      on_conflict: {:replace, [:revoked_at]},
      conflict_target: [:application_id, :user_id]
    )

    broadcast_revoke(app, user_id, :all)
  end

  def revoke(%App{} = app, user_id, grants)
      when is_binary(user_id) and user_id != "" and is_list(grants) and grants != [] do
    if Enum.all?(grants, &Grant.valid?(app.slug, &1)),
      do: broadcast_revoke(app, user_id, grants),
      else: {:error, :invalid}
  end

  def revoke(_app, _user_id, _grants), do: {:error, :invalid}

  defp broadcast_revoke(app, user_id, grants) do
    Phoenix.PubSub.broadcast(
      Eventbus.PubSub,
      subscriber_topic(app.id, user_id),
      {:revoke_topics, grants}
    )
  end

  @doc """
  The PubSub topic a joined channel listens on for its user's revocations.
  """
  def subscriber_topic(app_id, user_id), do: "topic_subscriber:#{app_id}:#{user_id}"

  @doc """
  Whether a revocation with `grants` (`:all` or patterns) covers `topic_name`.
  """
  def revoked_topic?(:all, _topic_name), do: true
  def revoked_topic?(grants, topic_name), do: Enum.any?(grants, &Grant.matches?(&1, topic_name))

  @doc """
  Turns `require_topic_tokens` on or off for `app`.
  """
  def set_required(%App{} = app, required?) when is_boolean(required?) do
    with {:ok, app} <-
           app |> Ecto.Changeset.change(require_topic_tokens: required?) |> Repo.update() do
      refresh_cache()
      {:ok, app}
    end
  end

  @doc """
  Whether the app with `slug` refuses topic joins without a token. Checked
  on every join, so cached in `:persistent_term`.
  """
  def required?(slug) do
    slugs =
      case :persistent_term.get(@cache, nil) do
        nil -> refresh_cache()
        slugs -> slugs
      end

    MapSet.member?(slugs, slug)
  end

  @doc """
  Rebuilds the cache of apps that require tokens. Call after toggling the
  setting or deleting an app.
  """
  def refresh_cache do
    slugs = Repo.all(from a in App, where: a.require_topic_tokens, select: a.slug) |> MapSet.new()
    :persistent_term.put(@cache, slugs)
    slugs
  end
end
