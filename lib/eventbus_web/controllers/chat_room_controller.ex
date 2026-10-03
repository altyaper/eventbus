defmodule EventbusWeb.ChatRoomController do
  @moduledoc """
  The server-side chat API, for an app's backend: create rooms, manage their
  members and send messages as one of its users (e.g. a bot). Users are named
  by the app's external ids and created on first mention.
  """

  use EventbusWeb, :controller

  alias Eventbus.Chat.{Broadcast, Caller, Messages, Rooms, Serializer, User, Users}

  action_fallback EventbusWeb.ChatFallbackController

  def create(%{assigns: %{current_app: app}} = conn, %{"type" => "direct"} = params) do
    with [a, b] when is_binary(a) and is_binary(b) <- List.wrap(params["members"]),
         {:ok, room, events} <- Rooms.create_direct_room(app, a, b) do
      Broadcast.dispatch(app, events)
      room_created(conn, room, events)
    else
      {:error, _reason} = error -> error
      _not_two_members -> {:error, :invalid}
    end
  end

  def create(%{assigns: %{current_app: app}} = conn, params) do
    opts = [members: List.wrap(params["members"]), created_by: params["created_by"]]

    with {:ok, room, events} <- Rooms.create_room(app, Map.take(params, ["name", "type"]), opts) do
      Broadcast.dispatch(app, events)
      room_created(conn, room, events)
    end
  end

  # An existing direct room comes back with 200 and no events.
  defp room_created(conn, room, events) do
    conn
    |> put_status(if events == [], do: :ok, else: :created)
    |> json(%{
      room: Serializer.room(room),
      members: room |> Rooms.list_members() |> Enum.map(&Serializer.member/1)
    })
  end

  def add_member(%{assigns: %{current_app: app}} = conn, %{"room_id" => room_id} = params) do
    with {:ok, room} <- fetch_room(app, room_id),
         {:ok, member, events} <-
           Rooms.add_member(app, room, params["user_id"], params["role"] || "member") do
      Broadcast.dispatch(app, events)

      conn
      |> put_status(if events == [], do: :ok, else: :created)
      |> json(%{member: Serializer.member(member)})
    end
  end

  def remove_member(%{assigns: %{current_app: app}} = conn, %{
        "room_id" => room_id,
        "user_id" => user_id
      }) do
    with {:ok, room} <- fetch_room(app, room_id),
         {:ok, _member, events} <- Rooms.remove_member(app, room, user_id) do
      Broadcast.dispatch(app, events)
      send_resp(conn, :no_content, "")
    end
  end

  def create_message(%{assigns: %{current_app: app}} = conn, %{"room_id" => room_id} = params) do
    with {:ok, room} <- fetch_room(app, room_id),
         %User{} = user <- Users.get_user(app, params["user_id"]) || {:error, :not_found},
         attrs = Map.take(params, ["text", "client_ref", "metadata"]),
         {:ok, message, events} <- Messages.send_message(Caller.new(app, user), room, attrs) do
      Broadcast.dispatch(app, events)

      conn
      |> put_status(if events == [], do: :ok, else: :created)
      |> json(%{message: Serializer.message(message)})
    end
  end

  defp fetch_room(app, room_id) do
    case Rooms.get_app_room(app, room_id) do
      nil -> {:error, :not_found}
      room -> {:ok, room}
    end
  end
end
