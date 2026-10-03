defmodule Eventbus.Chat.Rooms do
  @moduledoc """
  Chat rooms and their members. The app's backend manages membership over
  the HTTP API; chat users can only open rooms they belong to, or public
  rooms of their app, which they join by opening.

  Changes return `{:ok, result, events}`; hand the events to
  `Eventbus.Chat.Broadcast.dispatch/2`. A room of another app is always
  `:not_found`, so ids from other tenants can't be probed.
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Eventbus.Repo
  alias Eventbus.Applications.App
  alias Eventbus.Chat.{Caller, Member, Message, Room, Serializer, User, Users}

  @doc """
  The app's rooms, latest activity first, each with `:members_count`.
  """
  def list_app_rooms(%App{id: app_id}) do
    Repo.all(
      from r in Room,
        where: r.application_id == ^app_id,
        left_join: m in assoc(r, :members),
        group_by: r.id,
        order_by: [desc: coalesce(r.last_message_at, r.inserted_at), desc: r.id],
        select: %{r | members_count: count(m.id)}
    )
  end

  @doc """
  The app's room with `id` (an integer or a string), or `nil`.
  """
  def get_app_room(%App{id: app_id}, id) do
    case parse_id(id) do
      {:ok, id} -> Repo.get_by(Room, id: id, application_id: app_id)
      :error -> nil
    end
  end

  def change_room(attrs \\ %{}), do: Room.changeset(%Room{}, attrs)

  @doc """
  Creates a group or public room. `opts[:members]` are external ids to add
  as members (created as users if new); `opts[:created_by]` is added as a
  moderator.
  """
  def create_room(%App{} = app, attrs, opts \\ []) do
    Multi.new()
    |> Multi.run(:creator, fn _repo, _changes -> maybe_user(app, opts[:created_by]) end)
    |> Multi.insert(:room, fn %{creator: creator} ->
      Room.changeset(
        %Room{application_id: app.id, created_by_id: creator && creator.id},
        attrs
      )
    end)
    |> Multi.run(:members, fn _repo, %{room: room, creator: creator} ->
      creator_member = if creator, do: [{creator.external_id, "moderator"}], else: []
      others = for id <- List.wrap(opts[:members]), id != opts[:created_by], do: {id, "member"}
      insert_members(app, room, creator_member ++ others)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{room: room, members: members}} ->
        {:ok, room, Enum.flat_map(members, &added_events(room, &1))}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  The direct room of two of the app's users, created (with both as members)
  if it doesn't exist yet. Users are created if new; the same user twice is
  `{:error, :same_user}`.
  """
  def create_direct_room(%App{}, external_id, external_id), do: {:error, :same_user}

  def create_direct_room(%App{} = app, external_id_a, external_id_b) do
    with {:ok, a} <- Users.get_or_create_user(app, external_id_a),
         {:ok, b} <- Users.get_or_create_user(app, external_id_b) do
      key = Room.direct_key(a, b)

      case Repo.get_by(Room, application_id: app.id, direct_key: key) do
        %Room{} = room -> {:ok, room, []}
        nil -> insert_direct_room(app, key, [a, b])
      end
    end
  end

  defp insert_direct_room(app, key, users) do
    Multi.new()
    |> Multi.insert(
      :room,
      %Room{application_id: app.id, type: "direct", direct_key: key},
      on_conflict: :nothing,
      conflict_target: [:application_id, :direct_key]
    )
    |> Multi.run(:members, fn _repo, %{room: room} ->
      if room.id,
        do: insert_members(app, room, Enum.map(users, &{&1.external_id, "member"})),
        else: {:ok, :lost_race}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{members: :lost_race}} ->
        {:ok, Repo.get_by!(Room, application_id: app.id, direct_key: key), []}

      {:ok, %{room: room, members: members}} ->
        {:ok, room, Enum.flat_map(members, &added_events(room, &1))}

      {:error, _step, reason, _changes} ->
        {:error, reason}
    end
  end

  @doc """
  Adds the app's user `external_id` to `room` (creating the user if new), or
  changes their role if they're already a member. Direct rooms keep their two
  members: `{:error, :direct_room}`.
  """
  def add_member(app, room, external_id, role \\ "member")

  def add_member(_app, %Room{type: "direct"}, _external_id, _role), do: {:error, :direct_room}

  def add_member(%App{} = app, %Room{} = room, external_id, role) do
    with {:ok, user} <- Users.get_or_create_user(app, external_id) do
      case get_member(room, user) do
        nil ->
          with {:ok, member} <- insert_member(room, user, role) do
            {:ok, member, added_events(room, member)}
          end

        %Member{role: ^role} = member ->
          {:ok, member, []}

        member ->
          with {:ok, member} <- member |> Member.changeset(%{role: role}) |> Repo.update() do
            {:ok, %{member | user: user}, []}
          end
      end
    end
  end

  @doc """
  Removes the app's user `external_id` from `room`. Their messages stay.
  """
  def remove_member(_app, %Room{type: "direct"}, _external_id), do: {:error, :direct_room}

  def remove_member(%App{} = app, %Room{} = room, external_id) do
    with %User{} = user <- Users.get_user(app, external_id),
         %Member{} = member <- get_member(room, user) do
      {:ok, member} = Repo.delete(member)
      member = %{member | user: user}

      {:ok, member,
       [
         {:room, room, "chat.member.left",
          %{room_id: room.id, member: Serializer.member(member)}},
         {:user, user, "room.member.removed", %{room_id: room.id}}
       ]}
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  The room's members with their users, oldest first.
  """
  def list_members(%Room{id: room_id}) do
    Repo.all(
      from m in Member,
        where: m.room_id == ^room_id,
        join: u in assoc(m, :user),
        order_by: [asc: m.joined_at, asc: m.id],
        preload: [user: u]
    )
  end

  def get_member(%Room{id: room_id}, %User{id: user_id}),
    do: Repo.get_by(Member, room_id: room_id, chat_user_id: user_id)

  def member?(%Room{id: room_id}, %User{id: user_id}),
    do:
      Repo.exists?(from m in Member, where: m.room_id == ^room_id and m.chat_user_id == ^user_id)

  @doc """
  The room `room_id` if the caller may open it: they're a member, or it's a
  public room of their app, which they join now (hence the events).
  `{:error, :not_found}` otherwise.
  """
  def open_room(%Caller{app: app, user: user}, room_id) do
    with %Room{} = room <- get_app_room(app, room_id) do
      cond do
        member?(room, user) ->
          {:ok, room, []}

        room.type == "public" ->
          case insert_member(room, user, "member") do
            {:ok, member} -> {:ok, room, added_events(room, member)}
            # Joined from another tab at the same moment.
            {:error, _changeset} -> {:ok, room, []}
          end

        true ->
          {:error, :not_found}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  @doc """
  The caller's rooms for their sidebar, latest activity first: each as
  `%{room, last_message, members}`, where `members` is only loaded for
  direct rooms (to show the other person).
  """
  def list_user_rooms(%Caller{user: %User{id: user_id}}) do
    rooms =
      Repo.all(
        from r in Room,
          join: m in assoc(r, :members),
          where: m.chat_user_id == ^user_id,
          order_by: [desc: coalesce(r.last_message_at, r.inserted_at), desc: r.id]
      )

    last_messages =
      case Enum.flat_map(rooms, &List.wrap(&1.last_message_id)) do
        [] ->
          %{}

        ids ->
          Repo.all(from msg in Message, where: msg.id in ^ids, preload: :sender)
          |> Map.new(&{&1.id, &1})
      end

    direct_members =
      case for(r <- rooms, r.type == "direct", do: r.id) do
        [] ->
          %{}

        ids ->
          Repo.all(from m in Member, where: m.room_id in ^ids, preload: :user)
          |> Enum.group_by(& &1.room_id)
      end

    Enum.map(rooms, fn room ->
      %{
        room: room,
        last_message: last_messages[room.last_message_id],
        members: Map.get(direct_members, room.id, [])
      }
    end)
  end

  defp maybe_user(_app, nil), do: {:ok, nil}
  defp maybe_user(app, external_id), do: Users.get_or_create_user(app, external_id)

  defp insert_members(app, room, ids_and_roles) do
    ids_and_roles
    |> Enum.uniq_by(&elem(&1, 0))
    |> Enum.reduce_while({:ok, []}, fn {external_id, role}, {:ok, acc} ->
      with {:ok, user} <- Users.get_or_create_user(app, external_id),
           {:ok, member} <- insert_member(room, user, role) do
        {:cont, {:ok, [member | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, members} -> {:ok, Enum.reverse(members)}
      error -> error
    end
  end

  defp insert_member(room, user, role) do
    %Member{room_id: room.id, chat_user_id: user.id}
    |> Member.changeset(%{role: role})
    |> Repo.insert()
    |> case do
      {:ok, member} -> {:ok, %{member | user: user}}
      error -> error
    end
  end

  defp added_events(room, %Member{user: user} = member) do
    [
      {:room, room, "chat.member.joined", %{room_id: room.id, member: Serializer.member(member)}},
      {:user, user, "room.member.added", %{room: Serializer.room(room)}}
    ]
  end

  defp parse_id(id) when is_integer(id), do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _other -> :error
    end
  end

  defp parse_id(_id), do: :error
end
