defmodule Eventbus.TopicTokensTest do
  # Not async: the required-apps cache is global.
  use Eventbus.DataCase, async: false

  import Eventbus.ApplicationsFixtures

  alias Eventbus.{Applications, Repo, TopicTokens}

  setup do
    on_exit(fn -> :persistent_term.erase({TopicTokens, :required_slugs}) end)
    %{app: app_fixture(slug: "acme")}
  end

  defp mint!(app, attrs) do
    {:ok, %{token: token}} =
      TopicTokens.mint(app, Map.merge(%{"user_id" => "u1", "grants" => ["acme.board.*"]}, attrs))

    token
  end

  describe "mint/2" do
    test "returns a token that verifies for granted topics", %{app: app} do
      {:ok, %{token: token, expires_at: expires_at}} =
        TopicTokens.mint(app, %{"user_id" => "u1", "grants" => ["acme.board.*", "acme.user.u1"]})

      assert DateTime.diff(expires_at, DateTime.utc_now()) in 895..900

      assert {:ok, %{app: app_id, sub: "u1"}} = TopicTokens.verify(token, "acme.board.ab12")
      assert app_id == app.id
      assert {:ok, _} = TopicTokens.verify(token, "acme.user.u1")
    end

    test "honours ttl", %{app: app} do
      {:ok, %{expires_at: expires_at}} =
        TopicTokens.mint(app, %{"user_id" => "u1", "grants" => ["acme.x"], "ttl" => 60})

      assert DateTime.diff(expires_at, DateTime.utc_now()) in 55..60
    end

    test "validates its input", %{app: app} do
      assert {:error, changeset} = TopicTokens.mint(app, %{})
      assert %{user_id: ["can't be blank"], grants: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               TopicTokens.mint(app, %{"user_id" => "u1", "grants" => ["other.x", "acme.ok"]})

      assert %{grants: [message]} = errors_on(changeset)
      assert message =~ "other.x"
      refute message =~ "acme.ok"

      too_many = for i <- 1..101, do: "acme.t#{i}"

      assert {:error, changeset} =
               TopicTokens.mint(app, %{"user_id" => "u1", "grants" => too_many})

      assert %{grants: [_]} = errors_on(changeset)

      for ttl <- [0, 3601] do
        assert {:error, changeset} =
                 TopicTokens.mint(app, %{"user_id" => "u1", "grants" => ["acme.x"], "ttl" => ttl})

        assert %{ttl: [_]} = errors_on(changeset)
      end
    end
  end

  describe "verify/2" do
    test "forbids topics outside the grants", %{app: app} do
      token = mint!(app, %{})
      assert TopicTokens.verify(token, "acme.board") == {:error, :forbidden}
      assert TopicTokens.verify(token, "acme.user.u1") == {:error, :forbidden}
    end

    test "refuses garbage, tampered and chat tokens", %{app: app} do
      token = mint!(app, %{})
      assert TopicTokens.verify("garbage", "acme.board.x") == {:error, :invalid}
      assert TopicTokens.verify(nil, "acme.board.x") == {:error, :invalid}
      assert TopicTokens.verify(token <> "x", "acme.board.x") == {:error, :invalid}

      chat = Phoenix.Token.sign(EventbusWeb.Endpoint, "chat user", {app.id, 1})
      assert TopicTokens.verify(chat, "acme.board.x") == {:error, :invalid}
    end

    test "refuses expired tokens", %{app: app} do
      past = System.system_time(:microsecond) - 1_000_000

      expired =
        Phoenix.Token.sign(EventbusWeb.Endpoint, "topic grants", %{
          app: app.id,
          sub: "u1",
          grants: ["acme.x"],
          iat: past - 60_000_000,
          exp: past
        })

      assert TopicTokens.verify(expired, "acme.x") == {:error, :expired}
    end

    test "tokens stop working when the app is deleted", %{app: app} do
      token = mint!(app, %{})
      {:ok, _} = Applications.delete_app(app)
      assert TopicTokens.verify(token, "acme.board.x") == {:error, :invalid}
    end
  end

  describe "revoke/3" do
    test "a full revocation refuses older tokens, not newer ones", %{app: app} do
      old = mint!(app, %{})
      :ok = TopicTokens.revoke(app, "u1")
      assert TopicTokens.verify(old, "acme.board.x") == {:error, :revoked}

      new = mint!(app, %{})
      assert {:ok, _} = TopicTokens.verify(new, "acme.board.x")

      other_user = mint!(app, %{"user_id" => "u2"})
      assert {:ok, _} = TopicTokens.verify(other_user, "acme.board.x")
    end

    test "revoking again moves the cutoff", %{app: app} do
      :ok = TopicTokens.revoke(app, "u1")
      token = mint!(app, %{})
      :ok = TopicTokens.revoke(app, "u1")
      assert TopicTokens.verify(token, "acme.board.x") == {:error, :revoked}
      assert Repo.aggregate(Eventbus.TopicTokens.Revocation, :count) == 1
    end

    test "broadcasts to the user's channels", %{app: app} do
      Phoenix.PubSub.subscribe(Eventbus.PubSub, TopicTokens.subscriber_topic(app.id, "u1"))

      :ok = TopicTokens.revoke(app, "u1", ["acme.board.ab12.*"])
      assert_receive {:revoke_topics, ["acme.board.ab12.*"]}

      :ok = TopicTokens.revoke(app, "u1")
      assert_receive {:revoke_topics, :all}
    end

    test "a grant revocation leaves tokens valid", %{app: app} do
      token = mint!(app, %{})
      :ok = TopicTokens.revoke(app, "u1", ["acme.board.*"])
      assert {:ok, _} = TopicTokens.verify(token, "acme.board.x")
    end

    test "rejects bad input", %{app: app} do
      assert TopicTokens.revoke(app, "u1", ["other.x"]) == {:error, :invalid}
      assert TopicTokens.revoke(app, "u1", []) == {:error, :invalid}
      assert TopicTokens.revoke(app, "", nil) == {:error, :invalid}
      assert TopicTokens.revoke(app, nil, nil) == {:error, :invalid}
    end
  end

  describe "required?/1" do
    test "follows the app setting and app deletion", %{app: app} do
      refute TopicTokens.required?("acme")

      {:ok, app} = TopicTokens.set_required(app, true)
      assert TopicTokens.required?("acme")

      {:ok, app} = TopicTokens.set_required(app, false)
      refute TopicTokens.required?("acme")

      {:ok, app} = TopicTokens.set_required(app, true)
      {:ok, _} = Applications.delete_app(app)
      refute TopicTokens.required?("acme")
    end
  end
end
