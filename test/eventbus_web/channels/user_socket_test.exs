defmodule EventbusWeb.UserSocketTest do
  use EventbusWeb.ChannelCase, async: true

  alias EventbusWeb.{OriginHeader, UserSocket}

  test "keeps the origin header the endpoint copied" do
    assert {:ok, socket} =
             connect(UserSocket, %{},
               connect_info: %{x_headers: [{"x-eventbus-origin", "https://changologs.com"}]}
             )

    assert socket.assigns.origin == URI.parse("https://changologs.com")
  end

  test "has no origin when the request had none" do
    assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{x_headers: []})
    assert socket.assigns.origin == nil
  end

  describe "chat tokens" do
    setup do
      app = Eventbus.ApplicationsFixtures.app_fixture()

      {:ok, %{token: token, user: user}} =
        Eventbus.Chat.Tokens.mint(app, %{external_id: "ann", display_name: "Ann"})

      %{token: token, user: user}
    end

    test "a valid token makes a chat socket with an id", %{token: token, user: user} do
      assert {:ok, socket} =
               connect(UserSocket, %{"token" => token}, connect_info: %{x_headers: []})

      assert socket.assigns.chat_caller.user.id == user.id
      assert UserSocket.id(socket) == "chat_socket:#{user.id}"
    end

    test "a bad token is refused" do
      assert :error = connect(UserSocket, %{"token" => "nope"}, connect_info: %{x_headers: []})
    end

    test "no token stays anonymous" do
      assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{x_headers: []})
      refute Map.has_key?(socket.assigns, :chat_caller)
      assert UserSocket.id(socket) == nil
    end
  end

  describe "OriginHeader.put/1" do
    test "copies Origin into the header" do
      conn =
        Plug.Test.conn(:get, "/socket/websocket")
        |> Plug.Conn.put_req_header("origin", "https://changologs.com")
        |> OriginHeader.put()

      assert Plug.Conn.get_req_header(conn, "x-eventbus-origin") == ["https://changologs.com"]
    end

    test "drops a client-sent copy" do
      spoofed =
        Plug.Test.conn(:get, "/socket/websocket")
        |> Plug.Conn.put_req_header("x-eventbus-origin", "https://changologs.com")

      assert spoofed |> OriginHeader.put() |> Plug.Conn.get_req_header("x-eventbus-origin") == []

      overwritten =
        spoofed
        |> Plug.Conn.put_req_header("origin", "https://evil.example")
        |> OriginHeader.put()

      assert Plug.Conn.get_req_header(overwritten, "x-eventbus-origin") == [
               "https://evil.example"
             ]
    end
  end
end
