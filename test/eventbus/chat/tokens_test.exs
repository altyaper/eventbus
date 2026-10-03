defmodule Eventbus.Chat.TokensTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures

  alias Eventbus.Chat.{Caller, Tokens, Users}

  setup do
    %{app: app_fixture()}
  end

  test "mint upserts the user and the token verifies to them", %{app: app} do
    {:ok, %{token: token, user: user, expires_at: expires_at}} =
      Tokens.mint(app, %{external_id: "ann", display_name: "Ann"})

    assert DateTime.diff(expires_at, DateTime.utc_now()) in 3590..3600
    assert {:ok, %Caller{app: %{id: app_id}, user: %{id: user_id}}} = Tokens.verify(token)
    assert {app_id, user_id} == {app.id, user.id}

    {:ok, %{user: again}} =
      Tokens.mint(app, %{external_id: "ann", display_name: "Ann B", avatar_url: "https://a/b.png"})

    assert again.id == user.id
    assert Users.get_user(app, "ann").display_name == "Ann B"
  end

  test "mint validates the user", %{app: app} do
    assert {:error, changeset} = Tokens.mint(app, %{external_id: "has space", display_name: ""})
    assert %{external_id: [_], display_name: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects garbage, tampered and expired tokens", %{app: app} do
    {:ok, %{token: token}} = Tokens.mint(app, %{external_id: "ann", display_name: "Ann"})

    assert Tokens.verify("garbage") == :error
    assert Tokens.verify(nil) == :error
    assert Tokens.verify(token <> "x") == :error

    expired =
      Phoenix.Token.sign(EventbusWeb.Endpoint, "chat user", {app.id, 1},
        signed_at: System.system_time(:second) - 7200
      )

    assert Tokens.verify(expired) == :error
  end

  test "tokens stop working when the app is deleted", %{app: app} do
    {:ok, %{token: token}} = Tokens.mint(app, %{external_id: "ann", display_name: "Ann"})
    # Repo.delete, not Applications.delete_app: that refreshes the global
    # origin cache, which async tests mustn't touch.
    {:ok, _} = Eventbus.Repo.delete(app)
    assert Tokens.verify(token) == :error
  end
end
