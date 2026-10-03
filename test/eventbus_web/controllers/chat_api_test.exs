defmodule EventbusWeb.ChatApiTest do
  use EventbusWeb.ConnCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Broadcast, Messages, Rooms, Tokens, Users}

  setup %{conn: conn} do
    app = app_fixture(slug: "acme")
    auth = "Basic " <> Base.encode64("#{app.client_id}:#{app.secret}")
    %{app: app, conn: put_req_header(conn, "authorization", auth)}
  end

  describe "POST /api/chat/tokens" do
    test "mints a token for the user", %{conn: conn, app: app} do
      conn = post(conn, ~p"/api/chat/tokens", %{user_id: "ann", display_name: "Ann"})

      assert %{
               "token" => token,
               "expires_at" => _,
               "user" => %{"id" => "ann", "display_name" => "Ann"}
             } =
               json_response(conn, 201)

      assert {:ok, caller} = Tokens.verify(token)
      assert caller.app.id == app.id
    end

    test "422 for an invalid user", %{conn: conn} do
      conn = post(conn, ~p"/api/chat/tokens", %{user_id: "has space"})

      assert %{"error" => "invalid", "errors" => %{"display_name" => _, "external_id" => _}} =
               json_response(conn, 422)
    end

    test "401 without credentials" do
      conn = post(build_conn(), ~p"/api/chat/tokens", %{user_id: "ann", display_name: "Ann"})
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "POST /api/chat/rooms" do
    test "creates a group room with members and a moderator", %{conn: conn, app: app} do
      conn =
        post(conn, ~p"/api/chat/rooms", %{
          type: "group",
          name: "eng",
          members: ["ann", "bo"],
          created_by: "ann"
        })

      assert %{"room" => %{"id" => id, "name" => "eng", "type" => "group"}, "members" => members} =
               json_response(conn, 201)

      assert Enum.map(members, &{&1["user"]["id"], &1["role"]}) ==
               [{"ann", "moderator"}, {"bo", "member"}]

      assert Rooms.get_app_room(app, id)
    end

    test "creating a direct room twice returns the same room", %{conn: conn} do
      first = post(conn, ~p"/api/chat/rooms", %{type: "direct", members: ["ann", "bo"]})
      assert %{"room" => %{"id" => id, "type" => "direct"}} = json_response(first, 201)

      again = post(conn, ~p"/api/chat/rooms", %{type: "direct", members: ["bo", "ann"]})
      assert %{"room" => %{"id" => ^id}} = json_response(again, 200)
    end

    test "422 for bad rooms", %{conn: conn} do
      assert json_response(
               post(conn, ~p"/api/chat/rooms", %{type: "direct", members: ["ann"]}),
               422
             )

      assert json_response(
               post(conn, ~p"/api/chat/rooms", %{type: "direct", members: ["a", "a"]}),
               422
             )

      assert %{"errors" => %{"name" => _}} =
               json_response(post(conn, ~p"/api/chat/rooms", %{type: "group"}), 422)
    end

    test "broadcasts member additions to each user's topic", %{conn: conn} do
      Phoenix.PubSub.subscribe(Eventbus.PubSub, Broadcast.user_topic("acme", "ann"))
      post(conn, ~p"/api/chat/rooms", %{type: "group", name: "eng", members: ["ann"]})
      assert_receive {:chat_event, "room.member.added", %{room: %{name: "eng"}}}
    end
  end

  describe "members" do
    setup %{app: app} do
      %{room: room_fixture(app, %{name: "eng"})}
    end

    test "adds, updates and removes a member", %{conn: conn, app: app, room: room} do
      conn1 = post(conn, ~p"/api/chat/rooms/#{room.id}/members", %{user_id: "ann"})

      assert %{"member" => %{"user" => %{"id" => "ann"}, "role" => "member"}} =
               json_response(conn1, 201)

      conn2 =
        post(conn, ~p"/api/chat/rooms/#{room.id}/members", %{user_id: "ann", role: "moderator"})

      assert %{"member" => %{"role" => "moderator"}} = json_response(conn2, 200)

      conn3 = delete(conn, ~p"/api/chat/rooms/#{room.id}/members/ann")
      assert response(conn3, 204)
      refute Rooms.member?(room, Users.get_user(app, "ann"))

      assert json_response(delete(conn, ~p"/api/chat/rooms/#{room.id}/members/ann"), 404)
    end

    test "another app's room is a 404", %{conn: conn} do
      other_room = room_fixture(app_fixture())
      conn = post(conn, ~p"/api/chat/rooms/#{other_room.id}/members", %{user_id: "ann"})
      assert json_response(conn, 404) == %{"error" => "not found"}
    end

    test "422 for a bad role or user id", %{conn: conn, room: room} do
      assert json_response(
               post(conn, ~p"/api/chat/rooms/#{room.id}/members", %{user_id: "ann", role: "owner"}),
               422
             )

      assert json_response(
               post(conn, ~p"/api/chat/rooms/#{room.id}/members", %{user_id: "a b"}),
               422
             )
    end
  end

  describe "POST /api/chat/rooms/:room_id/messages" do
    setup %{app: app} do
      bot = chat_user_fixture(app, external_id: "bot", display_name: "Bot")
      %{room: room_fixture(app, %{}, [bot])}
    end

    test "sends as a member, idempotent by client_ref", %{conn: conn, room: room} do
      params = %{user_id: "bot", text: "deploying", client_ref: "d1"}
      first = post(conn, ~p"/api/chat/rooms/#{room.id}/messages", params)

      assert %{"message" => %{"id" => id, "sender" => %{"id" => "bot"}}} =
               json_response(first, 201)

      again = post(conn, ~p"/api/chat/rooms/#{room.id}/messages", params)
      assert %{"message" => %{"id" => ^id}} = json_response(again, 200)
      assert [_] = Messages.list_messages(room).messages
    end

    test "404 for unknown users and non-members", %{conn: conn, app: app, room: room} do
      chat_user_fixture(app, external_id: "outsider")

      for user_id <- ["nobody", "outsider"] do
        conn =
          post(conn, ~p"/api/chat/rooms/#{room.id}/messages", %{user_id: user_id, text: "hi"})

        assert json_response(conn, 404)
      end
    end
  end
end
