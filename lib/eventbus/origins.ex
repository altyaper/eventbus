defmodule Eventbus.Origins do
  @moduledoc """
  Origins allowed to open the LiveView and Channels websockets.

  Two sources: origins from the environment (`PHX_HOST` and
  `PHX_EXTRA_ORIGINS`), which can't be changed from the UI so the admin can't
  lock themselves out, and origins the superadmin adds in the UI, stored in
  `allowed_origins`.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Eventbus.Repo
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
  Origins added in the UI, oldest first.
  """
  def list_allowed_origins do
    Repo.all(from o in AllowedOrigin, order_by: [asc: o.inserted_at, asc: o.id])
  end

  def change_allowed_origin(%AllowedOrigin{} = allowed_origin, attrs \\ %{}) do
    AllowedOrigin.changeset(allowed_origin, attrs)
  end

  def create_allowed_origin(attrs) do
    %AllowedOrigin{}
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

  def delete_allowed_origin(id) do
    case Repo.get(AllowedOrigin, id) do
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
  websocket. Called on every connect, so patterns are cached in
  `:persistent_term` and refreshed on change.
  """
  def allowed?(%URI{} = origin) do
    Enum.any?(patterns(), &Pattern.matches?(&1, origin))
  end

  defp patterns do
    case :persistent_term.get(@cache, nil) do
      nil -> refresh_cache()
      patterns -> patterns
    end
  end

  @doc false
  def refresh_cache do
    patterns =
      (env_origins() ++ Enum.map(list_allowed_origins(), & &1.origin))
      |> Enum.flat_map(fn origin ->
        case Pattern.parse(origin) do
          {:ok, pattern} -> [pattern]
          :error -> []
        end
      end)

    :persistent_term.put(@cache, patterns)
    patterns
  end
end
