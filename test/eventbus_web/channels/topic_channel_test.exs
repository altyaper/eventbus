defmodule EventbusWeb.TopicChannelTest do
  use EventbusWeb.ChannelCase

  alias Eventbus.Topics

  setup do
    {:ok, _, socket} =
      EventbusWeb.UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:joins-test")

    %{socket: socket}
  end

  test "join auto-creates the topic if it doesn't exist yet" do
    assert {:ok, _topic} = Topics.get_or_create_by_name("joins-test")
  end

  test "join rejects an invalid topic name" do
    assert {:error, %{reason: "invalid topic name"}} =
             EventbusWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:Bad Name")
  end

  test "broadcasts on the topic are pushed to the client as \"event\"" do
    event = %{"topic" => "joins-test", "payload" => %{"a" => 1}, "published_at" => "now"}
    Phoenix.PubSub.broadcast(Eventbus.PubSub, "topic:joins-test", {:event, event})

    assert_push "event", ^event
  end

  test "handle_in publish/2 broadcasts and replies with the published event", %{socket: socket} do
    ref = push(socket, "publish", %{"hello" => "world"})
    assert_reply ref, :ok, event
    assert event["topic"] == "joins-test"
    assert event["payload"] == %{"hello" => "world"}
  end
end
