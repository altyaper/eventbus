defmodule Eventbus.Settings do
  @moduledoc """
  Instance-wide settings persisted in the `settings` table. Currently only the
  API key that gates HTTP publishing and the initial setup screen.
  """

  require Logger

  alias Eventbus.{Accounts, Repo}
  alias Eventbus.Settings.Setting

  @api_key_cache {__MODULE__, :api_key}

  @doc """
  Returns the instance API key, cached in `:persistent_term` after the first
  lookup so the publish plug never hits the database.
  """
  def api_key do
    case :persistent_term.get(@api_key_cache, nil) do
      nil -> cache_api_key!()
      key -> key
    end
  end

  @doc """
  Resolves the API key and caches it. An explicitly configured
  `EVENTBUS_API_KEY` wins; otherwise the key stored in the database is used,
  generating and persisting one on first boot.
  """
  def cache_api_key! do
    key = Application.get_env(:eventbus, :api_key) || get_or_create_api_key()
    :persistent_term.put(@api_key_cache, key)
    key
  end

  @doc """
  Fetches the stored API key, generating and storing a random one if there
  isn't one yet. Race-safe: concurrent callers all end up with the same key.
  """
  def get_or_create_api_key do
    Repo.insert!(%Setting{key: "api_key", value: generate_api_key()},
      on_conflict: :nothing,
      conflict_target: :key
    )

    Repo.get_by!(Setting, key: "api_key").value
  end

  defp generate_api_key do
    "eb_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end

  @doc """
  Supervision-tree entry: resolves the API key before the endpoint starts, so
  the app fails to boot rather than serving without one. Until the first user
  exists, logs the key so the owner can complete `/setup`.
  """
  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :boot, []}, restart: :temporary}
  end

  @doc false
  def boot do
    key = cache_api_key!()

    unless Accounts.any_users?() do
      Logger.info("""
      [eventbus] No admin user yet. Finish setup at /setup using this API key:
      [eventbus]   #{key}\
      """)
    end

    :ignore
  end
end
