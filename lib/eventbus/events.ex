defmodule Eventbus.Events do
  @moduledoc """
  Publishing events to a topic. Shared by the HTTP publish endpoint and the
  topic page's test form, so both produce the same envelope and broadcast the
  same way. Callers decide who may publish where; this only broadcasts.
  """

  @pubsub Eventbus.PubSub

  @doc """
  Wraps `payload` in the event envelope and broadcasts it to every listener
  on `topic_name`. Returns `{:ok, event}` with the envelope.
  """
  def publish(topic_name, payload) do
    event = %{
      "topic" => topic_name,
      "payload" => payload,
      "published_at" => DateTime.utc_now()
    }

    Phoenix.PubSub.broadcast(@pubsub, pubsub_topic(topic_name), {:event, event})
    {:ok, event}
  end

  @doc """
  The `Phoenix.PubSub` / channel topic string for a given topic name.
  """
  def pubsub_topic(topic_name), do: "topic:#{topic_name}"
end
