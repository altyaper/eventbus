defmodule Eventbus.Events do
  @moduledoc """
  Publishing events to a topic. The single code path shared by the HTTP
  publish endpoint and the WebSocket channel's "publish" message, so both
  produce the same envelope and broadcast the same way.
  """

  alias Eventbus.Topics

  @pubsub Eventbus.PubSub

  @doc """
  Wraps `payload` in the event envelope, creates the topic if it doesn't
  exist yet, and broadcasts it to every listener on `topic_name`.

  Returns `{:ok, event}` with the full envelope that was broadcast, or
  `{:error, changeset}` if `topic_name` is invalid.
  """
  def publish(topic_name, payload) do
    case Topics.get_or_create_by_name(topic_name) do
      {:ok, _topic} ->
        event = %{
          "topic" => topic_name,
          "payload" => payload,
          "published_at" => DateTime.utc_now()
        }

        Phoenix.PubSub.broadcast(@pubsub, pubsub_topic(topic_name), {:event, event})
        {:ok, event}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  The `Phoenix.PubSub` / channel topic string for a given topic name.
  """
  def pubsub_topic(topic_name), do: "topic:#{topic_name}"
end
