defmodule Eventbus.Chat.Users do
  @moduledoc """
  Chat users, keyed by their application and the app's external id.
  """

  import Ecto.Query, warn: false

  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.Chat.User

  @doc """
  Creates the app's user with `attrs.external_id`, or updates their display
  name and avatar. Called on every token mint, so profiles follow the app.
  """
  def upsert_user(%App{id: app_id}, attrs) do
    %User{application_id: app_id}
    |> User.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:display_name, :avatar_url, :updated_at]},
      conflict_target: [:application_id, :external_id],
      returning: true
    )
  end

  @doc """
  The app's user with `external_id`, created with the id as display name if
  they haven't connected yet (e.g. added to a room before their first token).
  """
  def get_or_create_user(%App{id: app_id} = app, external_id) do
    case get_user(app, external_id) do
      nil ->
        %User{application_id: app_id}
        |> User.changeset(%{external_id: external_id, display_name: external_id})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:application_id, :external_id])
        |> case do
          {:ok, _user} -> {:ok, get_user(app, external_id)}
          {:error, changeset} -> {:error, changeset}
        end

      user ->
        {:ok, user}
    end
  end

  def get_user(%App{id: app_id}, external_id) when is_binary(external_id),
    do: Repo.get_by(User, application_id: app_id, external_id: external_id)

  def get_user(_app, _external_id), do: nil

  @doc """
  The ids of all of the app's chat users, e.g. to disconnect their sockets.
  """
  def list_user_ids(%App{id: app_id}),
    do: Repo.all(from u in User, where: u.application_id == ^app_id, select: u.id)
end
