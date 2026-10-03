defmodule Eventbus.OriginsTest do
  # Not async: the pattern cache and :env_origins are global.
  use Eventbus.DataCase, async: false

  # The invalid env origin below logs a warning on purpose.
  @moduletag :capture_log

  alias Eventbus.Origins

  setup do
    previous = Application.get_env(:eventbus, :env_origins)
    Application.put_env(:eventbus, :env_origins, ["eventbus.example.dev", "not an origin"])
    Origins.refresh_cache()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:eventbus, :env_origins, previous),
        else: Application.delete_env(:eventbus, :env_origins)

      :persistent_term.erase({Origins, :patterns})
    end)
  end

  test "env origins are allowed and invalid ones are skipped" do
    assert Origins.env_origins() == ["eventbus.example.dev"]
    assert Origins.allowed?(URI.parse("https://eventbus.example.dev"))
  end

  test "added origins are stored canonically and allowed right away" do
    refute Origins.allowed?(URI.parse("https://changologs.com"))

    assert {:ok, origin} = Origins.create_allowed_origin(%{origin: "HTTPS://Changologs.com/"})
    assert origin.origin == "https://changologs.com"
    assert Origins.allowed?(URI.parse("https://changologs.com"))
  end

  test "removed origins stop being allowed" do
    {:ok, origin} = Origins.create_allowed_origin(%{origin: "localhost:5173"})
    assert Origins.allowed?(URI.parse("http://localhost:5173"))

    assert {:ok, _} = Origins.delete_allowed_origin(origin.id)
    refute Origins.allowed?(URI.parse("http://localhost:5173"))
    assert {:error, :not_found} = Origins.delete_allowed_origin(origin.id)
  end

  test "rejects invalid and duplicate origins" do
    assert {:error, changeset} = Origins.create_allowed_origin(%{origin: "https://x.com/path"})
    assert [_message] = errors_on(changeset).origin

    {:ok, _} = Origins.create_allowed_origin(%{origin: "https://x.com"})
    assert {:error, changeset} = Origins.create_allowed_origin(%{origin: "https://X.com/"})
    assert "is already allowed" in errors_on(changeset).origin
  end

  test "works as the endpoint's check_origin callback" do
    {:ok, _} = Origins.create_allowed_origin(%{origin: "https://changologs.com"})

    check = fn origin ->
      Plug.Test.conn(:get, "/socket/websocket")
      |> Plug.Conn.put_req_header("origin", origin)
      |> Phoenix.Socket.Transport.check_origin(EventbusWeb.UserSocket, EventbusWeb.Endpoint,
        check_origin: {Origins, :allowed?, []}
      )
    end

    refute check.("https://changologs.com").halted
    assert %Plug.Conn{halted: true, status: 403} = check.("https://evil.example")
  end
end
