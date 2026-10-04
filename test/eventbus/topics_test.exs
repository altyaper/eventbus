defmodule Eventbus.TopicsTest do
  use Eventbus.DataCase

  import Eventbus.ApplicationsFixtures
  import Eventbus.TopicsFixtures

  alias Eventbus.Topics
  alias Eventbus.Topics.Topic

  describe "create_topic/2" do
    test "creates a topic in the app" do
      app = app_fixture(slug: "chat")

      assert {:ok, %Topic{} = topic} = Topics.create_topic(app, %{name: "chat.lobby"})
      assert topic.name == "chat.lobby"
      assert topic.application_id == app.id
    end

    test "requires the app's slug as prefix" do
      app = app_fixture(slug: "chat")

      assert {:error, changeset} = Topics.create_topic(app, %{name: "other.lobby"})
      assert "must start with chat." in errors_on(changeset).name

      assert {:error, changeset} = Topics.create_topic(app, %{name: "chatter.x"})
      assert "must start with chat." in errors_on(changeset).name
    end

    test "rejects invalid names" do
      app = app_fixture(slug: "chat")
      assert {:error, changeset} = Topics.create_topic(app, %{name: "chat.Bad Name"})
      assert errors_on(changeset).name != []
    end
  end

  describe "get_or_create_app_topic/2" do
    test "creates the topic when it doesn't exist yet" do
      app = app_fixture(slug: "chat")
      assert {:ok, topic} = Topics.get_or_create_app_topic(app, "chat.new")
      assert topic.application_id == app.id
    end

    test "returns the existing topic" do
      existing = topic_fixture(name: "chat.lobby")
      app = app_with_slug("chat")
      assert {:ok, topic} = Topics.get_or_create_app_topic(app, "chat.lobby")
      assert topic.id == existing.id
    end

    test "refuses names outside the app" do
      app = app_fixture(slug: "chat")
      topic_fixture(name: "other.x")

      assert {:error, :forbidden} = Topics.get_or_create_app_topic(app, "other.x")
      assert {:error, :forbidden} = Topics.get_or_create_app_topic(app, "chatter.x")
    end
  end

  test "delete_topic/1 deletes the topic" do
    topic = topic_fixture()
    assert {:ok, %Topic{}} = Topics.delete_topic(topic)
    refute Topics.get_topic_by_name(topic.name)
  end

  describe "list_app_topic_level/2" do
    test "groups topics by their next name segment" do
      app = app_fixture(slug: "chat")

      for name <- ~w(chat.lobby chat.board chat.board.a chat.board.b chat.board.x.y chat.dm.z),
          do: topic_fixture(name: name)

      topic_fixture(name: "other.board.a")

      top = Topics.list_app_topic_level(app, "")
      assert top.groups == [{"board", 3}, {"dm", 1}]
      assert top.topics |> Enum.map(& &1.name) |> Enum.sort() == ~w(chat.board chat.lobby)

      board = Topics.list_app_topic_level(app, "board")
      assert board.groups == [{"x", 1}]
      assert board.topics |> Enum.map(& &1.name) |> Enum.sort() == ~w(chat.board.a chat.board.b)

      assert Topics.list_app_topic_level(app, "nope") == %{groups: [], topics: []}
    end
  end

  describe "valid_name?/1" do
    test "accepts lowercase alphanumeric names with '.', '-', '_'" do
      assert Topics.valid_name?("changologs.logs")
      assert Topics.valid_name?("my-app_events.v1")
    end

    test "rejects names with spaces, uppercase, or empty strings" do
      refute Topics.valid_name?("some name")
      refute Topics.valid_name?("Some.Name")
      refute Topics.valid_name?("")
      refute Topics.valid_name?(nil)
    end
  end
end
