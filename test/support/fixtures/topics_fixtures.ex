defmodule Eventbus.TopicsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Eventbus.Topics` context.
  """

  @doc """
  Generate a unique topic name.
  """
  def unique_topic_name, do: "some-name-#{System.unique_integer([:positive])}"

  @doc """
  Generate a topic.
  """
  def topic_fixture(attrs \\ %{}) do
    {:ok, topic} =
      attrs
      |> Enum.into(%{
        name: unique_topic_name()
      })
      |> Eventbus.Topics.create_topic()

    topic
  end
end
