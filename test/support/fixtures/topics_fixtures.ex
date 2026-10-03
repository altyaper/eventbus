defmodule Eventbus.TopicsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Eventbus.Topics` context.
  """

  import Eventbus.ApplicationsFixtures

  @doc """
  Generate a topic. Its application is `attrs[:app]`, or the one named by the
  name's prefix (created if needed), so `topic_fixture(name: "chat.lobby")`
  lands in app `chat`.
  """
  def topic_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    app = Map.get_lazy(attrs, :app, fn -> app_for(attrs[:name]) end)
    name = Map.get(attrs, :name, "#{app.slug}.topic-#{System.unique_integer([:positive])}")

    {:ok, topic} = Eventbus.Topics.create_topic(app, %{name: name})
    topic
  end

  defp app_for(nil), do: app_fixture()
  defp app_for(name), do: name |> String.split(".", parts: 2) |> hd() |> app_with_slug()
end
