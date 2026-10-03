defmodule EventbusWeb.ChatRoomLive do
  @moduledoc """
  One chat room inside its app, for the admin: its members and its message
  history, newest first, and who's online, updated live from the same events
  chat clients get. Managing members and deleting messages (moderation) are
  superadmin-only.
  """

  use EventbusWeb, :live_view

  import EventbusWeb.AppComponents

  alias Eventbus.Applications
  alias Eventbus.Accounts.Scope
  alias Eventbus.Chat.{Broadcast, Member, Messages, Presence, Rooms, Serializer}

  @impl true
  def mount(%{"slug" => slug, "id" => id}, _session, socket) do
    with {:app, app} when not is_nil(app) <- {:app, Applications.get_app_by_slug(slug)},
         {:room, room} when not is_nil(room) <- {:room, Rooms.get_app_room(app, id)} do
      if connected?(socket), do: Broadcast.subscribe_room(app, room)

      members = room |> Rooms.list_members() |> Enum.map(&Serializer.member/1)
      page = Messages.list_messages(room)

      {:ok,
       socket
       |> assign(:page_title, room_label(room))
       |> assign(:app, app)
       |> assign(:room, room)
       |> assign(:superadmin?, Scope.superadmin?(socket.assigns.current_scope))
       |> assign(:members_count, length(members))
       |> assign(:messages_count, length(page.messages))
       |> assign(:oldest_id, oldest_id(page.messages))
       |> assign(:has_more, page.has_more)
       |> assign_online()
       |> assign_member_form(%{"user_id" => "", "role" => "member"})
       |> stream_configure(:members, dom_id: &"member-#{&1.user.id}")
       |> stream_configure(:messages, dom_id: &"message-#{&1.id}")
       |> stream(:members, members)
       |> stream(:messages, page.messages |> Enum.reverse() |> Enum.map(&Serializer.message/1))}
    else
      {:app, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "There's no application #{slug}.")
         |> push_navigate(to: ~p"/apps")}

      {:room, nil} ->
        {:ok,
         socket
         |> put_flash(:error, "That room doesn't exist in #{slug}.")
         |> push_navigate(to: ~p"/apps/#{slug}/chat")}
    end
  end

  @impl true
  def handle_event("load_older", _params, socket) do
    page = Messages.list_messages(socket.assigns.room, before: socket.assigns.oldest_id)

    {:noreply,
     socket
     |> assign(:has_more, page.has_more)
     |> assign(:oldest_id, oldest_id(page.messages) || socket.assigns.oldest_id)
     |> update(:messages_count, &(&1 + length(page.messages)))
     |> stream(:messages, page.messages |> Enum.reverse() |> Enum.map(&Serializer.message/1))}
  end

  def handle_event(_event, _params, %{assigns: %{superadmin?: false}} = socket) do
    {:noreply, put_flash(socket, :error, "Only the superadmin can do that.")}
  end

  def handle_event("add_member", %{"member" => params}, socket) do
    %{app: app, room: room} = socket.assigns
    user_id = String.trim(params["user_id"] || "")

    case Rooms.add_member(app, room, user_id, params["role"] || "member") do
      {:ok, member, events} ->
        Broadcast.dispatch(app, events)

        {:noreply,
         socket
         |> put_flash(:info, "#{member.user.external_id} is a #{member.role} now.")
         # A role change has no event, so show it here; joins arrive as events.
         |> stream_insert(:members, Serializer.member(member))
         |> assign_member_form(%{"user_id" => "", "role" => "member"})}

      {:error, :direct_room} ->
        {:noreply, put_flash(socket, :error, "Direct rooms always have their two members.")}

      {:error, changeset} ->
        {:noreply, assign_member_form(socket, params, member_errors(changeset))}
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    %{app: app, room: room} = socket.assigns

    with {id, ""} <- Integer.parse(id),
         {:ok, _message, events} <- Messages.delete_message_as_app(app, room, id) do
      # The deleted event updates the message in place.
      Broadcast.dispatch(app, events)
    end

    {:noreply, socket}
  end

  def handle_event("remove_member", %{"user-id" => user_id}, socket) do
    %{app: app, room: room} = socket.assigns

    case Rooms.remove_member(app, room, user_id) do
      {:ok, member, events} ->
        Broadcast.dispatch(app, events)
        {:noreply, put_flash(socket, :info, "Removed #{member.user.external_id}.")}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:chat_event, "chat.message.created", %{message: message}}, socket) do
    {:noreply,
     socket
     |> update(:messages_count, &(&1 + 1))
     |> stream_insert(:messages, message, at: 0)}
  end

  def handle_info({:chat_event, event, %{message: message}}, socket)
      when event in ["chat.message.updated", "chat.message.deleted"] do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  # Reaction events only name the message, so reload that one message.
  def handle_info({:chat_event, "chat.reaction." <> _, %{message_id: id}}, socket) do
    case Messages.get_room_message(socket.assigns.room, id) do
      nil -> {:noreply, socket}
      message -> {:noreply, stream_insert(socket, :messages, Serializer.message(message))}
    end
  end

  def handle_info({:chat_event, "chat.member.joined", %{member: member}}, socket) do
    {:noreply,
     socket
     |> update(:members_count, &(&1 + 1))
     |> stream_insert(:members, member)}
  end

  def handle_info({:chat_event, "chat.member.left", %{member: member}}, socket) do
    {:noreply,
     socket
     |> update(:members_count, &(&1 - 1))
     |> stream_delete(:members, member)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign_online(socket)}

  def handle_info({:chat_event, _name, _payload}, socket), do: {:noreply, socket}

  # Re-listing on each diff is fine at admin scale and avoids merging diffs.
  defp assign_online(socket) do
    online =
      Broadcast.room_topic(socket.assigns.app.slug, socket.assigns.room.id)
      |> Presence.list()
      |> Enum.map(fn {user_id, %{metas: [meta | _] = metas}} ->
        %{id: user_id, display_name: meta.display_name, connections: length(metas)}
      end)
      |> Enum.sort_by(& &1.display_name)

    assign(socket, :online, online)
  end

  defp oldest_id([]), do: nil
  defp oldest_id([oldest | _rest]), do: oldest.id

  defp assign_member_form(socket, params, errors \\ []) do
    assign(socket, :member_form, to_form(params, as: "member", errors: errors))
  end

  # The user id is checked by the user changeset, the role by the member's.
  defp member_errors(%Ecto.Changeset{errors: errors}) do
    Enum.map(errors, fn
      {:external_id, error} -> {:user_id, error}
      other -> other
    end)
  end

  defp format_time(datetime), do: Calendar.strftime(datetime, "%b %-d · %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} nav={:apps}>
      <.app_shell
        app={@app}
        active={:chat}
        superadmin?={@superadmin?}
        crumb={room_label(@room)}
        crumb_parent={:chat}
      >
        <div class="mb-6 flex items-center gap-3">
          <span class="grid size-10 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
            <.icon name={room_icon(@room.type)} class="size-5" />
          </span>
          <div class="min-w-0">
            <h2 id="room-title" class="truncate text-lg font-semibold">{room_label(@room)}</h2>
            <p class="text-sm text-base-content/50">
              {String.capitalize(@room.type)} room · joined as
              <code class="font-mono">chat:{@app.slug}:{@room.id}</code>
            </p>
          </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-[1fr_18rem]">
          <.card id="room-messages" class="lg:order-1">
            <div class="mb-4 flex items-baseline justify-between">
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                Messages
              </h3>
              <span class="flex items-center gap-1.5 text-xs text-base-content/50">
                <span class="relative flex size-2">
                  <span class="absolute inline-flex size-full animate-ping rounded-full bg-success opacity-60"></span>
                  <span class="relative inline-flex size-2 rounded-full bg-success"></span>
                </span>
                Live · newest first
              </span>
            </div>
            <ol id="messages" phx-update="stream" class="space-y-1">
              <li
                id="messages-empty"
                class="hidden py-6 text-center text-sm text-base-content/50 only:block"
              >
                No messages yet.
              </li>
              <li
                :for={{id, message} <- @streams.messages}
                id={id}
                class="group -mx-2 flex gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-base-content/[0.03]"
              >
                <span class="grid size-8 shrink-0 place-items-center rounded-full bg-gradient-to-br from-primary/25 to-accent/25 text-xs font-semibold uppercase text-primary">
                  {String.first(message.sender.display_name)}
                </span>
                <div class="min-w-0 flex-1">
                  <p class="flex items-baseline gap-2 text-sm">
                    <span class="font-semibold">{message.sender.display_name}</span>
                    <span class="truncate font-mono text-xs text-base-content/40">
                      {message.sender.id}
                    </span>
                    <time class="ml-auto shrink-0 text-xs tabular-nums text-base-content/40">
                      {format_time(message.inserted_at)}
                    </time>
                  </p>
                  <p
                    :if={message.reply_to}
                    class="mt-0.5 flex min-w-0 items-center gap-1 border-l-2 border-base-content/15 pl-2 text-xs text-base-content/50"
                  >
                    <.icon name="hero-arrow-uturn-left-micro" class="size-3 shrink-0" />
                    <span class="shrink-0 font-medium">{message.reply_to.sender.display_name}</span>
                    <span class="truncate">
                      {if message.reply_to.deleted,
                        do: "deleted message",
                        else: message.reply_to.text}
                    </span>
                  </p>
                  <%= if message.deleted_at do %>
                    <p class="text-sm italic text-base-content/40">This message was deleted</p>
                  <% else %>
                    <p class="whitespace-pre-wrap break-words text-sm text-base-content/90">
                      {message.text}<span
                        :if={message.edited_at}
                        class="ml-1 text-xs text-base-content/40"
                      >(edited)</span>
                    </p>
                    <div :if={message.reactions != []} class="mt-1 flex flex-wrap gap-1">
                      <span
                        :for={reaction <- message.reactions}
                        title={Enum.join(reaction.user_ids, ", ")}
                        class="inline-flex items-center gap-1 rounded-full bg-base-content/5 px-1.5 py-0.5 text-xs tabular-nums"
                      >
                        {reaction.emoji} {reaction.count}
                      </span>
                    </div>
                  <% end %>
                </div>
                <button
                  :if={@superadmin? and is_nil(message.deleted_at)}
                  id={"#{id}-delete"}
                  type="button"
                  phx-click="delete_message"
                  phx-value-id={message.id}
                  data-confirm="Delete this message for everyone?"
                  class="self-start rounded-md p-1 text-base-content/30 opacity-0 transition-all hover:bg-error/10 hover:text-error group-hover:opacity-100 focus:opacity-100"
                  aria-label="Delete message"
                >
                  <.icon name="hero-trash-micro" class="size-4" />
                </button>
              </li>
            </ol>
            <button
              :if={@has_more}
              id="load-older"
              type="button"
              phx-click="load_older"
              phx-disable-with="Loading…"
              class="mt-4 w-full rounded-full border border-base-content/10 py-2 text-sm font-medium text-base-content/70 transition-colors hover:bg-base-content/5"
            >
              Load older messages
            </button>
          </.card>

          <.card id="room-members" class="lg:order-2 lg:self-start">
            <div class="mb-3 flex items-baseline justify-between">
              <h3 class="text-sm font-semibold uppercase tracking-wider text-base-content/50">
                Members
              </h3>
              <span id="members-count" class="text-sm tabular-nums text-base-content/50">
                {@members_count}
              </span>
            </div>
            <div id="online" class="mb-3 flex flex-wrap items-center gap-1.5">
              <span
                :if={@online == []}
                id="online-empty"
                class="text-xs text-base-content/40"
              >
                Nobody connected
              </span>
              <span
                :for={user <- @online}
                id={"online-#{user.id}"}
                title={"#{user.connections} #{if user.connections == 1, do: "connection", else: "connections"}"}
                class="inline-flex items-center gap-1.5 rounded-full bg-success/10 px-2 py-0.5 text-xs font-medium text-success"
              >
                <span class="size-1.5 rounded-full bg-success"></span>{user.display_name}
              </span>
            </div>
            <ul id="members" phx-update="stream" class="divide-y divide-base-content/5">
              <li id="members-empty" class="hidden py-3 text-sm text-base-content/50 only:block">
                No members yet.
              </li>
              <li
                :for={{id, member} <- @streams.members}
                id={id}
                class="group flex items-center gap-2.5 py-2"
              >
                <span class="grid size-7 shrink-0 place-items-center rounded-full bg-base-content/5 text-xs font-semibold uppercase text-base-content/60">
                  {String.first(member.user.display_name)}
                </span>
                <span class="min-w-0 flex-1">
                  <span class="block truncate text-sm">{member.user.display_name}</span>
                  <span class="block truncate font-mono text-xs text-base-content/40">
                    {member.user.id}
                  </span>
                </span>
                <span
                  :if={member.role == "moderator"}
                  class="rounded-full bg-primary/10 px-2 py-0.5 text-xs font-medium text-primary"
                >
                  mod
                </span>
                <button
                  :if={@superadmin? and @room.type != "direct"}
                  id={"#{id}-remove"}
                  type="button"
                  phx-click="remove_member"
                  phx-value-user-id={member.user.id}
                  class="rounded-md p-1 text-base-content/30 opacity-0 transition-all hover:bg-error/10 hover:text-error group-hover:opacity-100 focus:opacity-100"
                  aria-label={"Remove #{member.user.display_name}"}
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </li>
            </ul>

            <.form
              :if={@superadmin? and @room.type != "direct"}
              for={@member_form}
              id="member-form"
              phx-submit="add_member"
              class="mt-4 border-t border-base-content/5 pt-4"
            >
              <.input
                field={@member_form[:user_id]}
                label="Add by user id"
                placeholder="the app's id for the user"
                autocomplete="off"
              />
              <div class="flex items-start gap-2">
                <div class="flex-1">
                  <.input
                    field={@member_form[:role]}
                    type="select"
                    options={Enum.map(Member.roles(), &{String.capitalize(&1), &1})}
                  />
                </div>
                <button
                  id="add-member"
                  type="submit"
                  class="mt-1 inline-flex shrink-0 items-center gap-1.5 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-primary-content shadow-md shadow-primary/25 transition-all hover:brightness-110 active:scale-95 phx-submit-loading:opacity-60"
                >
                  <.icon name="hero-plus-micro" class="size-4" /> Add
                </button>
              </div>
            </.form>
          </.card>
        </div>
      </.app_shell>
    </Layouts.app>
    """
  end
end
