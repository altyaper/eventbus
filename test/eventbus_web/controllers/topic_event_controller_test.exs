defmodule EventbusWeb.TopicEventControllerTest do
  use EventbusWeb.ConnCase

  alias Eventbus.Topics

  @api_key Application.compile_env(:eventbus, :api_key)

  describe "POST /api/topics/:name/events" do
    test "without an API key returns 401", %{conn: conn} do
      conn = post(conn, "/api/topics/some-topic/events", %{"hello" => "world"})
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "with the wrong API key returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong-key")
        |> post("/api/topics/some-topic/events", %{"hello" => "world"})

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "with a valid API key publishes and echoes the event", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@api_key}")
        |> post("/api/topics/some-topic/events", %{"hello" => "world"})

      assert %{"topic" => "some-topic", "payload" => %{"hello" => "world"}} =
               json_response(conn, 202)

      assert {:ok, %{name: "some-topic"}} = Topics.get_or_create_by_name("some-topic")
    end

    test "with an invalid topic name returns 422", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{@api_key}")
        |> post("/api/topics/Bad Name/events", %{"hello" => "world"})

      assert json_response(conn, 422) == %{"error" => "invalid topic name"}
    end
  end
end
