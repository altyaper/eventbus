defmodule Eventbus.ApplicationsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.AccountsFixtures
  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures

  alias Eventbus.{Applications, Topics}
  alias Eventbus.Accounts.Scope
  alias Eventbus.Applications.App

  setup do
    user = default_user()
    %{user: user, scope: Scope.for_user(user)}
  end

  describe "create_app/2" do
    test "returns the plain secret once and stores only its hash", %{scope: scope, user: user} do
      assert {:ok, %App{} = app} = Applications.create_app(scope, %{slug: " ChangoLogs "})

      assert app.slug == "changologs"
      assert app.owner_id == user.id
      assert "ebc_" <> _ = app.client_id
      assert "ebs_" <> _ = app.secret
      refute app.secret_hash == app.secret

      reloaded = Applications.get_app!(app.id)
      assert reloaded.secret == nil
      refute reloaded.secret_hash =~ app.secret
    end

    test "validates the slug", %{scope: scope} do
      assert {:error, changeset} = Applications.create_app(scope, %{slug: "has.dot"})

      assert "must be lowercase letters, digits, '-' or '_' (no dots)" in errors_on(changeset).slug

      app_fixture(slug: "taken")
      assert {:error, changeset} = Applications.create_app(scope, %{slug: "taken"})
      assert "is already taken" in errors_on(changeset).slug
    end

    test "refuses unconfirmed users" do
      scope = Scope.for_user(user_fixture(confirmed: false))
      assert {:error, :unconfirmed} = Applications.create_app(scope, %{slug: "nope"})
    end
  end

  describe "create_sandbox_app/1" do
    test "creates a sandbox-* app for an unconfirmed user" do
      user = user_fixture(confirmed: false)

      assert {:ok, %App{slug: "sandbox-" <> suffix} = app} = Applications.create_sandbox_app(user)
      assert String.length(suffix) == 6
      assert app.owner_id == user.id
      assert "ebs_" <> _ = app.secret
    end
  end

  describe "authenticate/2" do
    test "accepts the right secret only" do
      app = app_fixture()

      assert {:ok, %App{id: id}} = Applications.authenticate(app.client_id, app.secret)
      assert id == app.id
      assert :error = Applications.authenticate(app.client_id, "ebs_wrong")
      assert :error = Applications.authenticate("ebc_unknown", app.secret)
      assert :error = Applications.authenticate(nil, nil)
    end
  end

  test "regenerate_secret/1 invalidates the old secret" do
    app = app_fixture()
    assert {:ok, regenerated} = Applications.regenerate_secret(app)

    refute regenerated.secret == app.secret
    assert :error = Applications.authenticate(app.client_id, app.secret)
    assert {:ok, _} = Applications.authenticate(app.client_id, regenerated.secret)
  end

  test "delete_app/1 deletes the app's topics" do
    app = app_fixture()
    topic = topic_fixture(app: app)
    other = topic_fixture()

    assert {:ok, _} = Applications.delete_app(app)
    refute Topics.get_topic_by_name(topic.name)
    assert Topics.get_topic_by_name(other.name)
  end

  test "list_apps_with_topic_counts/1 lists own apps by slug with topic counts", %{scope: scope} do
    topic_fixture(name: "zeta.a")
    topic_fixture(name: "alpha.first")
    topic_fixture(name: "alpha.second")
    app_fixture(slug: "empty")
    app_fixture(slug: "theirs", owner: user_fixture())

    assert [
             %{slug: "alpha", topics_count: 2},
             %{slug: "empty", topics_count: 0},
             %{slug: "zeta", topics_count: 1}
           ] = Applications.list_apps_with_topic_counts(scope)
  end

  test "get_app_by_slug/1" do
    app = app_fixture(slug: "chat")
    assert Applications.get_app_by_slug("chat").id == app.id
    assert Applications.get_app_by_slug("nope") == nil
  end

  test "get_owned_app/2 hides other users' apps", %{scope: scope} do
    app = app_fixture(slug: "mine")
    app_fixture(slug: "theirs", owner: user_fixture())

    assert Applications.get_owned_app(scope, "mine").id == app.id
    assert Applications.get_owned_app(scope, "theirs") == nil
  end
end
