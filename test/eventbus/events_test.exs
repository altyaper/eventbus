defmodule Eventbus.EventsTest do
  use ExUnit.Case, async: true

  alias Eventbus.Events

  test "publish/2 builds the envelope and broadcasts it" do
    Phoenix.PubSub.subscribe(Eventbus.PubSub, Events.pubsub_topic("chat.lobby"))

    assert {:ok, event} = Events.publish("chat.lobby", %{"hello" => "world"})
    assert event["topic"] == "chat.lobby"
    assert event["payload"] == %{"hello" => "world"}
    assert %DateTime{} = event["published_at"]

    assert_received {:event, ^event}
  end
end
