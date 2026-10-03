defmodule Eventbus.EventsTest do
  use Eventbus.DataCase

  alias Eventbus.Events
  alias Eventbus.Topics

  test "publish/2 creates the topic, builds the envelope, and broadcasts it" do
    Phoenix.PubSub.subscribe(Eventbus.PubSub, Events.pubsub_topic("new-topic"))

    assert {:ok, event} = Events.publish("new-topic", %{"hello" => "world"})
    assert event["topic"] == "new-topic"
    assert event["payload"] == %{"hello" => "world"}
    assert %DateTime{} = event["published_at"]

    assert {:ok, _topic} = Topics.get_or_create_by_name("new-topic")
    assert_received {:event, ^event}
  end

  test "publish/2 returns an error for an invalid topic name" do
    assert {:error, %Ecto.Changeset{}} = Events.publish("Bad Name", %{})
  end
end
