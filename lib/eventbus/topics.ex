defmodule Eventbus.Topics do
  @moduledoc """
  The Topics context.
  """

  import Ecto.Query, warn: false
  alias Eventbus.Repo

  alias Eventbus.Topics.Topic

  @doc """
  Returns the list of topics.

  ## Examples

      iex> list_topics()
      [%Topic{}, ...]

  """
  def list_topics do
    Repo.all(Topic)
  end

  @doc """
  Returns topics grouped by `Topic.app/1`, as `%{app: app, topics: topics}`
  maps. Apps are sorted by name with ungrouped topics (`app: nil`) last, and
  topics within an app are newest first.
  """
  def list_topics_by_app do
    list_topics()
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.group_by(&Topic.app/1)
    |> Enum.sort_by(fn {app, _topics} -> {is_nil(app), app} end)
    |> Enum.map(fn {app, topics} -> %{app: app, topics: topics} end)
  end

  @doc """
  Deletes every topic in an app group (names starting with `"<app>."`).
  Returns the number of topics deleted.

  Topics are created on first use, so a publisher that keeps sending to the
  app brings its topics back.
  """
  def delete_app_topics(app) when is_binary(app) and app != "" do
    # "_" is a LIKE wildcard and valid in app names, so escape it.
    pattern = String.replace(app, "_", "\\_") <> ".%"
    {count, _} = Repo.delete_all(from t in Topic, where: like(t.name, ^pattern))
    count
  end

  @doc """
  Gets a single topic.

  Raises `Ecto.NoResultsError` if the Topic does not exist.

  ## Examples

      iex> get_topic!(123)
      %Topic{}

      iex> get_topic!(456)
      ** (Ecto.NoResultsError)

  """
  def get_topic!(id), do: Repo.get!(Topic, id)

  @doc """
  Creates a topic.

  ## Examples

      iex> create_topic(%{field: value})
      {:ok, %Topic{}}

      iex> create_topic(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_topic(attrs) do
    %Topic{}
    |> Topic.changeset(attrs)
    |> Repo.insert()
  end

  defdelegate valid_name?(name), to: Topic

  @doc """
  Fetches the topic with the given name, creating it first if it doesn't exist yet.

  Race-safe: if two processes try to create the same new topic at once, the
  unique index on `name` rejects the second insert and we re-fetch instead.
  """
  def get_or_create_by_name(name) do
    case Repo.get_by(Topic, name: name) do
      %Topic{} = topic ->
        {:ok, topic}

      nil ->
        case create_topic(%{name: name}) do
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
  Updates a topic.

  ## Examples

      iex> update_topic(topic, %{field: new_value})
      {:ok, %Topic{}}

      iex> update_topic(topic, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_topic(%Topic{} = topic, attrs) do
    topic
    |> Topic.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a topic.

  ## Examples

      iex> delete_topic(topic)
      {:ok, %Topic{}}

      iex> delete_topic(topic)
      {:error, %Ecto.Changeset{}}

  """
  def delete_topic(%Topic{} = topic) do
    Repo.delete(topic)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking topic changes.

  ## Examples

      iex> change_topic(topic)
      %Ecto.Changeset{data: %Topic{}}

  """
  def change_topic(%Topic{} = topic, attrs \\ %{}) do
    Topic.changeset(topic, attrs)
  end
end
