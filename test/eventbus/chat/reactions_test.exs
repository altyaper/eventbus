defmodule Eventbus.Chat.ReactionsTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{Messages, Reactions, Serializer}

  setup do
    app = app_fixture()
    ann = caller_fixture(app, external_id: "ann")
    bo = caller_fixture(app, external_id: "bo")
    room = room_fixture(app, %{}, [ann.user, bo.user])
    %{app: app, ann: ann, bo: bo, room: room, message: message_fixture(ann, room)}
  end

  defp reactions(room, message),
    do: Serializer.message(Messages.get_room_message(room, message.id)).reactions

  test "adds once per user and emoji, and aggregates", %{
    ann: ann,
    bo: bo,
    room: room,
    message: message
  } do
    assert {:ok, [{:room, _, "chat.reaction.added", %{user_id: "ann", emoji: "👍"}}]} =
             Reactions.add_reaction(ann, room, message.id, "👍")

    assert {:ok, []} = Reactions.add_reaction(ann, room, message.id, "👍")
    {:ok, [_]} = Reactions.add_reaction(bo, room, message.id, "👍")
    {:ok, [_]} = Reactions.add_reaction(bo, room, message.id, "❤️")

    assert reactions(room, message) == [
             %{emoji: "👍", count: 2, user_ids: ["ann", "bo"]},
             %{emoji: "❤️", count: 1, user_ids: ["bo"]}
           ]
  end

  test "removes, and removing again does nothing", %{ann: ann, room: room, message: message} do
    {:ok, [_]} = Reactions.add_reaction(ann, room, message.id, "🎉")

    assert {:ok, [{:room, _, "chat.reaction.removed", %{emoji: "🎉"}}]} =
             Reactions.remove_reaction(ann, room, message.id, "🎉")

    assert {:ok, []} = Reactions.remove_reaction(ann, room, message.id, "🎉")
    assert reactions(room, message) == []
  end

  test "rejects unknown emoji, non-members, other rooms and deleted messages", %{
    app: app,
    ann: ann,
    room: room,
    message: message
  } do
    assert {:error, :invalid} = Reactions.add_reaction(ann, room, message.id, "hello")
    assert {:error, :invalid} = Reactions.add_reaction(ann, room, "1", "👍")

    assert {:error, :not_found} =
             Reactions.add_reaction(caller_fixture(app), room, message.id, "👍")

    other_room = room_fixture(app, %{}, [ann.user])
    assert {:error, :not_found} = Reactions.add_reaction(ann, other_room, message.id, "👍")

    {:ok, _, _} = Messages.delete_message(ann, room, message.id)
    assert {:error, :not_found} = Reactions.add_reaction(ann, room, message.id, "👍")
  end

  test "deleted messages don't show reactions", %{ann: ann, room: room, message: message} do
    {:ok, [_]} = Reactions.add_reaction(ann, room, message.id, "👍")
    {:ok, _, _} = Messages.delete_message(ann, room, message.id)
    assert reactions(room, message) == []
  end
end
