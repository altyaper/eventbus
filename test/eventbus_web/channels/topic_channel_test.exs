defmodule EventbusWeb.TopicChannelTest do
  use EventbusWeb.ChannelCase

  import Eventbus.ApplicationsFixtures

  alias Eventbus.{Origins, Topics, TopicTokens}

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

  describe "topic tokens" do
    setup do
      on_exit(fn ->
        :persistent_term.erase({Origins, :patterns})
        :persistent_term.erase({TopicTokens, :required_slugs})
      end)

      %{app: app_fixture(slug: "acme")}
    end

    defp token!(app, grants, user_id \\ "u1") do
      {:ok, %{token: token}} = TopicTokens.mint(app, %{"user_id" => user_id, "grants" => grants})
      token
    end

    defp join_with(topic, params) do
      EventbusWeb.UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:" <> topic, params)
    end

    test "a token that grants the topic may join", %{app: app} do
      assert {:ok, _, _} =
               join_with("acme.board.ab12", %{"token" => token!(app, ["acme.board.*"])})
    end

    test "a token that doesn't grant the topic is forbidden", %{app: app} do
      token = token!(app, ["acme.board.ab12"])
      assert {:error, %{reason: "forbidden"}} = join_with("acme.board.zz99", %{"token" => token})
    end

    test "another app's token is forbidden on this app's topics", %{app: app} do
      other = app_fixture(slug: "other")
      {:ok, _} = TopicTokens.set_required(app, true)

      assert {:error, %{reason: "forbidden"}} =
               join_with("acme.board.ab12", %{"token" => token!(other, ["other.*"])})
    end

    test "a bad token is refused even where anonymous joins are allowed" do
      assert {:error, %{reason: "invalid token"}} =
               join_with("acme.board.ab12", %{"token" => "x"})
    end

    test "a revoked token is refused", %{app: app} do
      token = token!(app, ["acme.board.*"])
      :ok = TopicTokens.revoke(app, "u1")
      assert {:error, %{reason: "token revoked"}} = join_with("acme.board.x", %{"token" => token})
    end

    test "an expired token is refused", %{app: app} do
      past = System.system_time(:microsecond) - 1_000_000

      token =
        Phoenix.Token.sign(EventbusWeb.Endpoint, "topic grants", %{
          app: app.id,
          sub: "u1",
          grants: ["acme.x"],
          iat: past - 1_000_000,
          exp: past
        })

      assert {:error, %{reason: "token expired"}} = join_with("acme.x", %{"token" => token})
    end

    test "an app that requires tokens refuses anonymous joins, others don't", %{app: app} do
      {:ok, _} = TopicTokens.set_required(app, true)
      assert {:error, %{reason: "unauthorized"}} = join_with("acme.board.x", %{})
      assert {:ok, _, _} = join_with("chat.lobby", %{})
    end

    test "the origin check still applies with a token", %{app: app} do
      {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://acme.com"})

      assert {:error, %{reason: "origin not allowed"}} =
               EventbusWeb.UserSocket
               |> socket(nil, %{origin: URI.parse("https://evil.example")})
               |> subscribe_and_join(EventbusWeb.TopicChannel, "topic:acme.x", %{
                 "token" => token!(app, ["acme.x"])
               })
    end

    test "revoking a matching grant closes the channel", %{app: app} do
      {:ok, _, socket} = join_with("acme.board.ab12", %{"token" => token!(app, ["acme.board.*"])})
      Process.unlink(socket.channel_pid)
      ref = Process.monitor(socket.channel_pid)

      :ok = TopicTokens.revoke(app, "u1", ["acme.board.ab12"])

      assert_push "revoked", %{}
      assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :revoked}}
    end

    test "revocations of other topics or users leave the channel open", %{app: app} do
      {:ok, _, _} = join_with("acme.board.ab12", %{"token" => token!(app, ["acme.board.*"])})

      :ok = TopicTokens.revoke(app, "u1", ["acme.board.zz99"])
      :ok = TopicTokens.revoke(app, "u2")

      # Still delivering after both revocations were handled.
      Phoenix.PubSub.broadcast(Eventbus.PubSub, "topic:acme.board.ab12", {:event, %{"n" => 1}})
      assert_push "event", %{"n" => 1}
      refute_push "revoked", _
    end

    test "a full revocation closes every channel of the user", %{app: app} do
      token = token!(app, ["acme.*"])
      {:ok, _, a} = join_with("acme.board.ab12", %{"token" => token})
      {:ok, _, b} = join_with("acme.user.u1", %{"token" => token})
      refs = for s <- [a, b], do: Process.unlink(s.channel_pid) && Process.monitor(s.channel_pid)

      :ok = TopicTokens.revoke(app, "u1")

      for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _pid, {:shutdown, :revoked}})
    end
  end
end
