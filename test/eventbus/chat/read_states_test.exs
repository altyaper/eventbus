defmodule Eventbus.Chat.ReadStatesTest do
  use Eventbus.DataCase, async: true

  import Eventbus.ApplicationsFixtures
  import Eventbus.ChatFixtures

  alias Eventbus.Chat.{ReadStates, Rooms}
  alias Eventbus.Repo

  setup do
    app = app_fixture()
    ann = caller_fixture(app, external_id: "ann")
    bo = caller_fixture(app, external_id: "bo")
    %{app: app, ann: ann, bo: bo, room: room_fixture(app, %{}, [ann.user, bo.user])}
  end

  defp unread(caller, room),
    do: ReadStates.unread_counts(caller.user, [room.id]) |> Map.get(room.id, 0)

  test "counts others' messages after the read position", %{ann: ann, bo: bo, room: room} do
    first = message_fixture(bo, room)
    message_fixture(bo, room)
    message_fixture(ann, room)

    assert unread(ann, room) == 2
    assert unread(bo, room) == 1

    {:ok, read_state, [event]} = ReadStates.mark_read(ann, room, first.id)
    assert read_state.last_read_message_id == first.id
    assert {:user, _, "read_state.updated", %{unread_count: 1, last_read_message_id: id}} = event
    assert id == first.id
    assert unread(ann, room) == 1
  end

  test "positions only move forward", %{ann: ann, bo: bo, room: room} do
    first = message_fixture(bo, room)
    second = message_fixture(bo, room)

    {:ok, _, [_]} = ReadStates.mark_read(ann, room, second.id)
    {:ok, read_state, []} = ReadStates.mark_read(ann, room, first.id)
    assert read_state.last_read_message_id == second.id
    {:ok, _, []} = ReadStates.mark_read(ann, room, second.id)
  end

  test "rejects messages of other rooms", %{app: app, ann: ann, room: room} do
    other = room_fixture(app, %{}, [ann.user])
    message = message_fixture(ann, other)

    assert {:error, :not_found} = ReadStates.mark_read(ann, room, message.id)
    assert {:error, :invalid} = ReadStates.mark_read(ann, room, "1")
  end

  test "deleted messages and messages from before joining don't count", %{
    app: app,
    bo: bo,
    room: room
  } do
    deleted = message_fixture(bo, room)
    Repo.update!(Ecto.Changeset.change(deleted, deleted_at: DateTime.utc_now()))
    old = message_fixture(bo, room)
    # Pretend the message is from before anyone joined.
    Repo.update!(Ecto.Changeset.change(old, inserted_at: ~U[2020-01-01 00:00:00.000000Z]))

    {:ok, _member, _} = Rooms.add_member(app, room, "cy")
    cy = caller_fixture(app, external_id: "cy")

    assert unread(cy, room) == 0
    message_fixture(bo, room)
    assert unread(cy, room) == 1
  end

  test "rooms you're not in have no count", %{app: app, bo: bo} do
    outsider = caller_fixture(app)
    room = room_fixture(app, %{}, [bo.user])
    message_fixture(bo, room)
    assert unread(outsider, room) == 0
  end
end
