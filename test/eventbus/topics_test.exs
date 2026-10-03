defmodule Eventbus.TopicsTest do
  use Eventbus.DataCase

  alias Eventbus.Topics
  import Eventbus.TopicsFixtures

  describe "topics" do
    alias Eventbus.Topics.Topic

    @invalid_attrs %{name: nil}

    test "list_topics/0 returns all topics" do
      topic = topic_fixture()
      assert Topics.list_topics() == [topic]
    end

    test "list_topics_by_app/0 groups topics by name prefix, apps sorted, ungrouped last" do
      ungrouped = topic_fixture(name: "standalone")
      chat_lobby = topic_fixture(name: "chat.lobby")
      logs = topic_fixture(name: "changologs.logs")
      chat_team = topic_fixture(name: "chat.team")

      assert [
               %{app: "changologs", topics: [^logs]},
               %{app: "chat", topics: chat_topics},
               %{app: nil, topics: [^ungrouped]}
             ] = Topics.list_topics_by_app()

      assert Enum.sort_by(chat_topics, & &1.id) == [chat_lobby, chat_team]
    end

    test "get_topic!/1 returns the topic with given id" do
      topic = topic_fixture()
      assert Topics.get_topic!(topic.id) == topic
    end

    test "create_topic/1 with valid data creates a topic" do
      valid_attrs = %{name: "some-name"}

      assert {:ok, %Topic{} = topic} = Topics.create_topic(valid_attrs)
      assert topic.name == "some-name"
    end

    test "create_topic/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Topics.create_topic(@invalid_attrs)
    end

    test "update_topic/2 with valid data updates the topic" do
      topic = topic_fixture()
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, %Topic{} = topic} = Topics.update_topic(topic, update_attrs)
      assert topic.name == "some-updated-name"
    end

    test "update_topic/2 with invalid data returns error changeset" do
      topic = topic_fixture()
      assert {:error, %Ecto.Changeset{}} = Topics.update_topic(topic, @invalid_attrs)
      assert topic == Topics.get_topic!(topic.id)
    end

    test "delete_topic/1 deletes the topic" do
      topic = topic_fixture()
      assert {:ok, %Topic{}} = Topics.delete_topic(topic)
      assert_raise Ecto.NoResultsError, fn -> Topics.get_topic!(topic.id) end
    end

    test "change_topic/1 returns a topic changeset" do
      topic = topic_fixture()
      assert %Ecto.Changeset{} = Topics.change_topic(topic)
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

  describe "get_or_create_by_name/1" do
    test "creates the topic when it doesn't exist yet" do
      assert {:ok, topic} = Topics.get_or_create_by_name("brand-new-topic")
      assert topic.name == "brand-new-topic"
    end

    test "returns the existing topic when it already exists" do
      existing = topic_fixture()
      assert {:ok, topic} = Topics.get_or_create_by_name(existing.name)
      assert topic.id == existing.id
    end

    test "returns an error changeset for an invalid name" do
      assert {:error, %Ecto.Changeset{}} = Topics.get_or_create_by_name("Bad Name")
    end
  end

  describe "Topic.app/1" do
    alias Eventbus.Topics.Topic

    test "is the part of the name before the first dot" do
      assert Topic.app(%Topic{name: "chat.lobby"}) == "chat"
      assert Topic.app(%Topic{name: "changologs.logs.errors"}) == "changologs"
    end

    test "is nil when the name has no dot" do
      assert Topic.app(%Topic{name: "standalone"}) == nil
    end
  end
end
