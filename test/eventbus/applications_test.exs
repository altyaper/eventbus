defmodule Eventbus.ApplicationsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures

  alias Eventbus.{Applications, Topics}
  alias Eventbus.Applications.App

  describe "create_app/1" do
    test "returns the plain secret once and stores only its hash" do
      assert {:ok, %App{} = app} = Applications.create_app(%{slug: " ChangoLogs "})

      assert app.slug == "changologs"
      assert "ebc_" <> _ = app.client_id
      assert "ebs_" <> _ = app.secret
      refute app.secret_hash == app.secret

      reloaded = Applications.get_app!(app.id)
      assert reloaded.secret == nil
      refute reloaded.secret_hash =~ app.secret
    end

    test "validates the slug" do
      assert {:error, changeset} = Applications.create_app(%{slug: "has.dot"})

      assert "must be lowercase letters, digits, '-' or '_' (no dots)" in errors_on(changeset).slug

      app_fixture(slug: "taken")
      assert {:error, changeset} = Applications.create_app(%{slug: "taken"})
      assert "is already taken" in errors_on(changeset).slug
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

  test "list_apps_with_topics/0 sorts apps by slug and topics newest first" do
    topic_fixture(name: "zeta.a")
    first = topic_fixture(name: "alpha.first")
    second = topic_fixture(name: "alpha.second")

    assert [%{slug: "alpha", topics: topics}, %{slug: "zeta"}] =
             Applications.list_apps_with_topics()

    assert Enum.map(topics, & &1.id) |> Enum.sort() == Enum.sort([first.id, second.id])
  end
end
