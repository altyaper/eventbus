defmodule Eventbus.Topics do
  @moduledoc """
  The Topics context. Every topic belongs to an application and is named
  `"<app slug>.<rest>"`.
  """

  import Ecto.Query, warn: false
  alias Eventbus.Repo

  alias Eventbus.Applications.App
  alias Eventbus.Topics.Topic

  @doc """
  Returns the list of topics.
  """
  def list_topics do
    Repo.all(Topic)
  end

  @doc """
  Gets a single topic.

  Raises `Ecto.NoResultsError` if the Topic does not exist.
  """
  def get_topic!(id), do: Repo.get!(Topic, id)

  @doc """
  Gets a topic by its full name, or `nil`.
  """
  def get_topic_by_name(name), do: Repo.get_by(Topic, name: name)

  @doc """
  Creates a topic in `app`. `attrs` carries the full name, slug included.
  """
  def create_topic(%App{} = app, attrs) do
    %Topic{}
    |> Topic.changeset(app, attrs)
    |> Repo.insert()
  end

  defdelegate valid_name?(name), to: Topic

  @doc """
  Fetches `app`'s topic with the given name, creating it first if it doesn't
  exist yet. Returns `{:error, :forbidden}` for a name outside the app.

  Race-safe: if two processes try to create the same new topic at once, the
  unique index on `name` rejects the second insert and we re-fetch instead.
  """
  def get_or_create_app_topic(%App{} = app, name) do
    cond do
      not String.starts_with?(name, app.slug <> ".") ->
        {:error, :forbidden}

      topic = get_topic_by_name(name) ->
        {:ok, topic}

      true ->
        case create_topic(app, %{name: name}) do
          {:ok, topic} -> {:ok, topic}
          {:error, changeset} -> retry_fetch_on_unique_conflict(changeset, name)
        end
    end
  end

  defp retry_fetch_on_unique_conflict(%Ecto.Changeset{errors: errors} = changeset, name) do
    unique_name_conflict? =
      Enum.any?(errors, fn
        {:name, {_msg, opts}} -> Keyword.get(opts, :constraint) == :unique
        _other -> false
      end)

    if unique_name_conflict? do
      {:ok, Repo.get_by!(Topic, name: name)}
    else
      {:error, changeset}
    end
  end

  @doc """
  Deletes a topic.
  """
  def delete_topic(%Topic{} = topic) do
    Repo.delete(topic)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking changes to a topic of `app`.
  """
  def change_topic(%App{} = app, attrs \\ %{}) do
    Topic.changeset(%Topic{}, app, attrs)
  end
end
