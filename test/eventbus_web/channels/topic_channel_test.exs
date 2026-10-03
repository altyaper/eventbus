defmodule EventbusWeb.TopicChannelTest do
  use EventbusWeb.ChannelCase

  import Eventbus.ApplicationsFixtures

  alias Eventbus.{Origins, Topics}

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

  describe "origins" do
    setup do
      on_exit(fn -> :persistent_term.erase({Origins, :patterns}) end)
      app = app_fixture(slug: "changologs")
      {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://changologs.com"})
      :ok
    end

    defp join_from(origin, topic) do
      EventbusWeb.UserSocket
      |> socket("user_id", %{origin: origin && URI.parse(origin)})
      |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:" <> topic)
    end

    test "an app's origin may join its topics" do
      assert {:ok, _, _} = join_from("https://changologs.com", "changologs.logs")
    end

    test "an app's origin may not join another app's topics" do
      assert {:error, %{reason: "origin not allowed"}} =
               join_from("https://changologs.com", "chat.lobby")
    end

    test "an unknown origin may not join" do
      assert {:error, %{reason: "origin not allowed"}} =
               join_from("https://evil.example", "changologs.logs")
    end

    test "sockets without an origin may join any topic" do
      assert {:ok, _, _} = join_from(nil, "chat.lobby")
    end
  end
end
