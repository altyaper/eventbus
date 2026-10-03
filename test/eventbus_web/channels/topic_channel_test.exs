defmodule EventbusWeb.TopicChannelTest do
  use EventbusWeb.ChannelCase

  alias Eventbus.Topics

  setup do
    {:ok, _, socket} =
      EventbusWeb.UserSocket
      |> socket("user_id", %{})
      |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:chat.lobby")

    %{socket: socket}
  end

  test "join works without creating a topic row" do
    refute Topics.get_topic_by_name("chat.lobby")
  end

  test "join rejects an invalid topic name" do
    assert {:error, %{reason: "invalid topic name"}} =
             EventbusWeb.UserSocket
             |> socket("user_id", %{})
             |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:Bad Name")
  end

  test "broadcasts on the topic are pushed to the client as \"event\"" do
    event = %{"topic" => "chat.lobby", "payload" => %{"a" => 1}, "published_at" => "now"}
    Phoenix.PubSub.broadcast(Eventbus.PubSub, "topic:chat.lobby", {:event, event})

    assert_push "event", ^event
  end

  # The crash from the unhandled message is expected; keep it out of the output.
  @tag :capture_log
  test "publishing over the channel is no longer supported", %{socket: socket} do
    Process.flag(:trap_exit, true)
    push(socket, "publish", %{"hello" => "world"})

    assert_receive {:EXIT, _pid, _reason}
    refute_push "event", _
  end
end
