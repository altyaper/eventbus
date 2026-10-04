defmodule EventbusWeb.TopicEventControllerTest do
  use EventbusWeb.ConnCase

  import Eventbus.ApplicationsFixtures

  alias Eventbus.Topics

  setup do
    %{app: app_fixture(slug: "chat")}
  end

  defp basic_auth(conn, client_id, secret) do
    put_req_header(conn, "authorization", "Basic " <> Base.encode64("#{client_id}:#{secret}"))
  end

  describe "POST /api/topics/:name/events" do
    test "publishes with valid credentials and creates the topic", %{conn: conn, app: app} do
      conn =
        conn
        |> basic_auth(app.client_id, app.secret)
        |> post("/api/topics/chat.lobby/events", %{"hello" => "world"})

      assert %{"topic" => "chat.lobby", "payload" => %{"hello" => "world"}} =
               json_response(conn, 202)

      assert Topics.get_topic_by_name("chat.lobby").application_id == app.id
    end

    test "returns 403 topic_limit past an unconfirmed owner's cap", %{conn: conn} do
      owner = Eventbus.AccountsFixtures.user_fixture(confirmed: false)
      app = app_fixture(slug: "sandbox-y", owner: owner)
      for i <- 1..5, do: Topics.create_topic(app, %{name: "sandbox-y.t#{i}"})

      conn =
        conn
        |> basic_auth(app.client_id, app.secret)
        |> post("/api/topics/sandbox-y.t6/events", %{"hello" => "world"})

      assert %{"error" => "topic_limit", "message" => "Confirm your email" <> _} =
               json_response(conn, 403)
    end

    test "returns 401 without credentials", %{conn: conn} do
      conn = post(conn, "/api/topics/chat.lobby/events", %{})
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 for a wrong secret or unknown client", %{conn: conn, app: app} do
      for {client_id, secret} <- [{app.client_id, "ebs_wrong"}, {"ebc_unknown", app.secret}] do
        conn =
          conn
          |> basic_auth(client_id, secret)
          |> post("/api/topics/chat.lobby/events", %{})

        assert json_response(conn, 401) == %{"error" => "unauthorized"}
      end

      refute Topics.get_topic_by_name("chat.lobby")
    end

    test "returns 401 for malformed or non-Basic headers", %{conn: conn} do
      for header <- ["Basic not-base64!", "Basic " <> Base.encode64("no-colon"), "Bearer x"] do
        conn =
          conn
          |> put_req_header("authorization", header)
          |> post("/api/topics/chat.lobby/events", %{})

        assert json_response(conn, 401) == %{"error" => "unauthorized"}
      end
    end

    test "returns 403 for another application's topic", %{conn: conn, app: app} do
      conn =
        conn
        |> basic_auth(app.client_id, app.secret)
        |> post("/api/topics/other.lobby/events", %{})

      assert json_response(conn, 403) == %{"error" => "topic belongs to another application"}
      refute Topics.get_topic_by_name("other.lobby")
    end

    test "returns 422 for an invalid topic name", %{conn: conn, app: app} do
      conn =
        conn
        |> basic_auth(app.client_id, app.secret)
        |> post("/api/topics/Bad Name/events", %{})

      assert json_response(conn, 422) == %{"error" => "invalid topic name"}
    end
  end
end
