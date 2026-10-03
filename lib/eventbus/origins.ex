defmodule Eventbus.Origins do
  @moduledoc """
  Origins whose web pages may open the websockets and listen to topics.

  Two sources: origins from the environment (`PHX_HOST` and
  `PHX_EXTRA_ORIGINS`), which can't be changed from the UI so the admin can't
  lock themselves out and which may listen to every app, and origins the
  superadmin adds to an application, which may only listen to that app's
  topics.

  Phoenix checks the origin when the socket connects, before it knows which
  topics will be joined, so enforcement has two steps: `allowed?/1` at
  connect (env origins or any app's) and `allowed_for_topic?/2` at join.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.Origins.{AllowedOrigin, Pattern}

  @cache {__MODULE__, :patterns}

  @doc """
  Origins configured through the environment, as canonical strings.
  """
  def env_origins do
    Application.get_env(:eventbus, :env_origins, [])
    |> Enum.flat_map(fn origin ->
      case Pattern.parse(origin) do
        {:ok, pattern} ->
          [Pattern.to_string(pattern)]

        :error ->
          Logger.warning(
            "[eventbus] Ignoring invalid origin #{inspect(origin)} from the environment"
          )

          []
      end
    end)
  end

  @doc """
  The origins added to `app`, oldest first.
  """
  def list_allowed_origins(%App{id: app_id}) do
    Repo.all(
      from o in AllowedOrigin,
        where: o.application_id == ^app_id,
        order_by: [asc: o.inserted_at, asc: o.id]
    )
  end

  def change_allowed_origin(%AllowedOrigin{} = allowed_origin, attrs \\ %{}) do
    AllowedOrigin.changeset(allowed_origin, attrs)
  end

  def create_allowed_origin(%App{id: app_id}, attrs) do
    %AllowedOrigin{application_id: app_id}
    |> AllowedOrigin.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, allowed_origin} ->
        refresh_cache()
        {:ok, allowed_origin}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Deletes one of `app`'s origins. Another app's origin id is `:not_found`.
  """
  def delete_allowed_origin(%App{id: app_id}, id) do
    case Repo.get_by(AllowedOrigin, id: id, application_id: app_id) do
      nil ->
        {:error, :not_found}

      allowed_origin ->
        {:ok, deleted} = Repo.delete(allowed_origin)
        refresh_cache()
        {:ok, deleted}
    end
  end

  @doc """
  The endpoint's `check_origin` callback: whether a browser origin may open a
  websocket at all, i.e. it's an env origin or allowed by some app. Which
  topics it may join is checked by `allowed_for_topic?/2`. Called on every
  connect, so patterns are cached in `:persistent_term` and refreshed on
  change.
  """
  def allowed?(%URI{} = origin) do
    %{env: env, by_app: by_app} = patterns()
    Enum.any?([env | Map.values(by_app)], &matches_any?(&1, origin))
  end

  @doc """
  Whether a socket opened from `origin` may listen to `topic_name`: env
  origins may listen to every topic, app origins only to their app's. A `nil`
  origin (no `Origin` header, so not a browser) is allowed, as Phoenix does
  at connect. Always true when the endpoint has origin checks turned off.
  """
  def allowed_for_topic?(nil, _topic_name), do: true

  def allowed_for_topic?(%URI{} = origin, topic_name) do
    %{env: env, by_app: by_app} = patterns()
    [slug | _rest] = String.split(topic_name, ".", parts: 2)

    not checks_enabled?() or matches_any?(env, origin) or
      matches_any?(Map.get(by_app, slug, []), origin)
  end

  @doc """
  False when the endpoint has `check_origin: false` (dev), in which case
  every origin is allowed and the lists don't apply.
  """
  def checks_enabled? do
    Application.get_env(:eventbus, EventbusWeb.Endpoint, [])[:check_origin] != false
  end

  defp matches_any?(patterns, origin), do: Enum.any?(patterns, &Pattern.matches?(&1, origin))

  defp patterns do
    case :persistent_term.get(@cache, nil) do
      nil -> refresh_cache()
      patterns -> patterns
    end
  end

  @doc """
  Rebuilds the pattern cache. Call after anything that changes which origins
  an app has, including deleting the app.
  """
  def refresh_cache do
    by_app =
      Repo.all(
        from o in AllowedOrigin, join: a in assoc(o, :application), select: {a.slug, o.origin}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {slug, origins} -> {slug, parse_all(origins)} end)

    patterns = %{env: parse_all(env_origins()), by_app: by_app}
    :persistent_term.put(@cache, patterns)
    patterns
  end

  defp parse_all(origins) do
    Enum.flat_map(origins, fn origin ->
      case Pattern.parse(origin) do
        {:ok, pattern} -> [pattern]
        :error -> []
      end
    end)
  end
end
