defmodule Eventbus.ChatFixtures do
  @moduledoc """
  Test helpers for chat users, rooms and messages.
  """

  alias Eventbus.Chat.{Caller, Messages, Rooms, Users}

  def unique_external_id, do: "user-#{System.unique_integer([:positive])}"

  def chat_user_fixture(app, attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> Enum.into(%{external_id: unique_external_id(), display_name: "Ann"})
      |> then(&Users.upsert_user(app, &1))

    user
  end

  def caller_fixture(app, attrs \\ %{}), do: Caller.new(app, chat_user_fixture(app, attrs))

  @doc """
  A group room (or `type: "public"`) of `app` with `members`, a list of chat
  users.
  """
  def room_fixture(app, attrs \\ %{}, members \\ []) do
    attrs = Enum.into(attrs, %{name: "room-#{System.unique_integer([:positive])}", type: "group"})

    {:ok, room, _events} =
      Rooms.create_room(app, attrs, members: Enum.map(members, & &1.external_id))

    room
  end

  def message_fixture(%Caller{} = caller, room, attrs \\ %{}) do
    {:ok, message, _events} =
      Messages.send_message(caller, room, Enum.into(attrs, %{"text" => "hello"}))

    message
  end
end
