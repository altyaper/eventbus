defmodule EventbusWeb.TopicTokenControllerTest do
  use EventbusWeb.ConnCase, async: true

  import Eventbus.ApplicationsFixtures

  alias Eventbus.TopicTokens

  setup %{conn: conn} do
    app = app_fixture(slug: "acme")
    auth = "Basic " <> Base.encode64("#{app.client_id}:#{app.secret}")
    %{app: app, conn: put_req_header(conn, "authorization", auth)}
  end

  describe "POST /api/tokens" do
    test "mints a token for the grants", %{conn: conn, app: app} do
      conn = post(conn, ~p"/api/tokens", %{user_id: "u1", grants: ["acme.board.*"], ttl: 60})

      assert %{"token" => token, "expires_at" => expires_at} = json_response(conn, 201)
      assert {:ok, %{app: app_id, sub: "u1"}} = TopicTokens.verify(token, "acme.board.ab12")
      assert app_id == app.id
      assert {:ok, _, _} = DateTime.from_iso8601(expires_at)
    end

    test "422 for grants outside the app", %{conn: conn} do
      conn = post(conn, ~p"/api/tokens", %{user_id: "u1", grants: ["other.x"]})
      assert %{"error" => "invalid", "errors" => %{"grants" => [_]}} = json_response(conn, 422)
    end

    test "401 without credentials" do
      conn = post(build_conn(), ~p"/api/tokens", %{user_id: "u1", grants: ["acme.x"]})
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "POST /api/tokens/revoke" do
    test "revokes grants or the whole user", %{conn: conn, app: app} do
      Phoenix.PubSub.subscribe(Eventbus.PubSub, TopicTokens.subscriber_topic(app.id, "u1"))

      assert conn
             |> post(~p"/api/tokens/revoke", %{user_id: "u1", grants: ["acme.board.*"]})
             |> response(204)

      assert_receive {:revoke_topics, ["acme.board.*"]}

      assert conn |> post(~p"/api/tokens/revoke", %{user_id: "u1"}) |> response(204)
      assert_receive {:revoke_topics, :all}
    end

    test "422 for a missing user or bad grants", %{conn: conn} do
      assert %{"error" => "invalid request"} =
               conn |> post(~p"/api/tokens/revoke", %{}) |> json_response(422)

      assert %{"error" => "invalid request"} =
               conn
               |> post(~p"/api/tokens/revoke", %{user_id: "u1", grants: ["other.x"]})
               |> json_response(422)
    end
  end
end
