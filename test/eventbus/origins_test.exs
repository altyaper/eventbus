defmodule Eventbus.OriginsTest do
  # Not async: the pattern cache and :env_origins are global.
  use Eventbus.DataCase, async: false

  # The invalid env origin below logs a warning on purpose.
  @moduletag :capture_log

  import Eventbus.ApplicationsFixtures

  alias Eventbus.{Applications, Origins}

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

    %{app: app_fixture(slug: "changologs")}
  end

  defp uri(origin), do: URI.parse(origin)

  test "env origins are allowed everywhere and invalid ones are skipped" do
    assert Origins.env_origins() == ["eventbus.example.dev"]
    assert Origins.allowed?(uri("https://eventbus.example.dev"))
    assert Origins.allowed_for_topic?(uri("https://eventbus.example.dev"), "changologs.logs")
    assert Origins.allowed_for_topic?(uri("https://eventbus.example.dev"), "other.logs")
  end

  test "added origins are stored canonically and allowed right away", %{app: app} do
    refute Origins.allowed?(uri("https://changologs.com"))

    assert {:ok, origin} =
             Origins.create_allowed_origin(app, %{origin: "HTTPS://Changologs.com/"})

    assert origin.origin == "https://changologs.com"
    assert origin.application_id == app.id
    assert Origins.allowed?(uri("https://changologs.com"))
    assert [%{origin: "https://changologs.com"}] = Origins.list_allowed_origins(app)
  end

  test "an app's origins may only listen to that app's topics", %{app: app} do
    other = app_fixture(slug: "chat")
    {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://changologs.com"})

    assert Origins.allowed_for_topic?(uri("https://changologs.com"), "changologs.logs")
    refute Origins.allowed_for_topic?(uri("https://changologs.com"), "chat.lobby")
    refute Origins.allowed_for_topic?(uri("https://changologs.com"), "changologsx.logs")
    assert Origins.list_allowed_origins(other) == []
  end

  test "requests without an Origin header may listen anywhere" do
    assert Origins.allowed_for_topic?(nil, "changologs.logs")
  end

  test "the topic check is skipped when origin checks are off" do
    previous = Application.get_env(:eventbus, EventbusWeb.Endpoint)

    Application.put_env(
      :eventbus,
      EventbusWeb.Endpoint,
      Keyword.put(previous, :check_origin, false)
    )

    on_exit(fn -> Application.put_env(:eventbus, EventbusWeb.Endpoint, previous) end)

    assert Origins.allowed_for_topic?(uri("https://evil.example"), "changologs.logs")
  end

  test "removed origins stop being allowed", %{app: app} do
    {:ok, origin} = Origins.create_allowed_origin(app, %{origin: "localhost:5173"})
    assert Origins.allowed?(uri("http://localhost:5173"))

    assert {:ok, _} = Origins.delete_allowed_origin(app, origin.id)
    refute Origins.allowed?(uri("http://localhost:5173"))
    assert {:error, :not_found} = Origins.delete_allowed_origin(app, origin.id)
  end

  test "an app can't delete another app's origin", %{app: app} do
    other = app_fixture(slug: "chat")
    {:ok, origin} = Origins.create_allowed_origin(app, %{origin: "https://changologs.com"})

    assert {:error, :not_found} = Origins.delete_allowed_origin(other, origin.id)
    assert Origins.allowed?(uri("https://changologs.com"))
  end

  test "deleting an app drops its origins from the cache", %{app: app} do
    {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://changologs.com"})

    {:ok, _} = Applications.delete_app(app)

    refute Origins.allowed?(uri("https://changologs.com"))
  end

  test "rejects invalid and duplicate origins, but two apps may share one", %{app: app} do
    assert {:error, changeset} =
             Origins.create_allowed_origin(app, %{origin: "https://x.com/path"})

    assert [_message] = errors_on(changeset).origin

    {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://x.com"})
    assert {:error, changeset} = Origins.create_allowed_origin(app, %{origin: "https://X.com/"})
    assert "is already allowed" in errors_on(changeset).origin

    assert {:ok, _} =
             Origins.create_allowed_origin(app_fixture(slug: "chat"), %{origin: "https://x.com"})
  end

  test "works as the endpoint's check_origin callback", %{app: app} do
    {:ok, _} = Origins.create_allowed_origin(app, %{origin: "https://changologs.com"})

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
