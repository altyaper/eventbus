// The chat demo page: a small Slack-like UI rendered with plain DOM on top of
// the headless chat SDK, as a consuming app would build its own. Demo code,
// not part of the SDK. The LiveView stands in for the app's backend and
// hands out tokens over pushEvent.

import {Chat, roomTitle} from "./chat/index"

const QUICK_EMOJI = ["👍", "❤️", "😂", "😮", "😢", "🎉", "🙏", "🔥"]
const RENDER_LIMIT = 500
const GROUP_WINDOW_MS = 5 * 60 * 1000

const esc = value =>
  String(value ?? "").replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c])

const hue = id => [...String(id)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) % 360, 7)

const time = iso => new Date(iso).toLocaleTimeString([], {hour: "2-digit", minute: "2-digit"})

const shortTime = iso => {
  if (!iso) return ""
  const date = new Date(iso)
  return date.toDateString() === new Date().toDateString()
    ? time(iso)
    : date.toLocaleDateString([], {month: "short", day: "numeric"})
}

// ---- Render functions (return HTML strings; all user content escaped) ----

function Avatar(user, size = "size-9") {
  const initial = esc((user.display_name || user.id || "?").slice(0, 1).toUpperCase())
  return `<span class="${size} grid shrink-0 place-items-center rounded-full text-sm font-semibold text-base-content/70"
    style="background: hsl(${hue(user.id)} 70% 85%)">${initial}</span>`
}

function RoomListItem(room, {me, activeId}) {
  const active = room.id === activeId
  const preview = room.last_message
    ? `${room.last_message.sender.id === me.id ? "You: " : ""}${room.last_message.deleted ? "Message deleted" : room.last_message.text}`
    : "No messages yet"
  const icon =
    room.type === "direct"
      ? Avatar(room.members.find(m => m.user.id !== me.id)?.user || {id: "?"}, "size-8")
      : `<span class="grid size-8 shrink-0 place-items-center rounded-lg bg-base-content/5 text-base-content/50"><span class="${room.type === "public" ? "hero-hashtag-micro" : "hero-lock-closed-micro"} size-4"></span></span>`
  const unread = room.unread_count > 0

  return `<li>
    <button type="button" data-action="open-room" data-room-id="${room.id}"
      class="group flex w-full items-center gap-3 rounded-xl px-2.5 py-2 text-left transition-colors ${active ? "bg-primary/10" : "hover:bg-base-content/5"}">
      ${icon}
      <span class="min-w-0 flex-1">
        <span class="flex items-baseline gap-2">
          <span class="truncate text-sm ${unread ? "font-semibold" : "font-medium"} ${active ? "text-primary" : ""}">${esc(roomTitle(room, me))}</span>
          <span class="ml-auto shrink-0 text-[11px] tabular-nums text-base-content/40">${esc(shortTime(room.last_message_at))}</span>
        </span>
        <span class="flex items-center gap-2">
          <span class="truncate text-xs ${unread ? "text-base-content/80" : "text-base-content/50"}">${esc(preview)}</span>
          ${unread ? `<span class="ml-auto grid h-5 min-w-5 shrink-0 place-items-center rounded-full bg-primary px-1.5 text-[11px] font-semibold tabular-nums text-primary-content">${room.unread_count > 99 ? "99+" : room.unread_count}</span>` : ""}
        </span>
      </span>
    </button>
  </li>`
}

function RoomList(rooms, ctx) {
  if (rooms.length === 0) {
    return `<li class="px-3 py-6 text-center text-sm text-base-content/50">No rooms yet.<br />Try <span class="font-medium">Seed sample rooms</span>.</li>`
  }
  return rooms.map(room => RoomListItem(room, ctx)).join("")
}

function PresenceIndicator(room, online, me) {
  if (room.type === "direct") {
    const other = room.members.find(m => m.user.id !== me.id)
    const isOnline = other && online.some(p => p.id === other.user.id)
    return `<span class="flex items-center gap-1.5 text-xs text-base-content/50">
      <span class="size-2 rounded-full ${isOnline ? "bg-success" : "bg-base-content/20"}"></span>${isOnline ? "Online" : "Offline"}
    </span>`
  }
  const avatars = online.slice(0, 4).map(p => `<span class="-ml-1.5 first:ml-0 rounded-full ring-2 ring-base-100" title="${esc(p.display_name)}">${Avatar(p, "size-6")}</span>`)
  return `<span class="flex items-center gap-2 text-xs text-base-content/50">
    <span class="flex">${avatars.join("")}</span>${online.length} online · ${room.members.length} members
  </span>`
}

function ChatHeader(room, {me, online, status}) {
  const title = roomTitle(room, me)
  const banner =
    status === "reconnecting"
      ? `<span class="rounded-full bg-warning/15 px-2 py-0.5 text-[11px] font-medium text-warning">Reconnecting…</span>`
      : status === "removed"
        ? `<span class="rounded-full bg-error/15 px-2 py-0.5 text-[11px] font-medium text-error">You were removed</span>`
        : ""
  return `<div class="flex items-center gap-3 border-b border-base-content/10 px-4 py-3">
    <button type="button" data-action="back" class="-ml-1 rounded-md p-1 text-base-content/60 hover:bg-base-content/5 md:hidden" aria-label="Back to rooms">←</button>
    <div class="min-w-0 flex-1">
      <h3 class="truncate font-semibold">${room.type === "public" ? "# " : ""}${esc(title)}</h3>
      ${PresenceIndicator(room, online, me)}
    </div>
    ${banner}
  </div>`
}

function ReplyPreview(reply, {compact = true} = {}) {
  if (!reply) return ""
  const body = reply.deleted ? `<span class="italic">Original message was deleted</span>` : esc(reply.text)
  return `<div class="${compact ? "mb-1" : ""} flex min-w-0 items-center gap-1.5 border-l-2 border-primary/40 pl-2 text-xs text-base-content/55">
    <span class="shrink-0 font-semibold text-base-content/70">${esc(reply.sender.display_name)}</span>
    <span class="truncate">${body}</span>
  </div>`
}

function ReactionList(message, me) {
  if (!message.reactions.length) return ""
  return `<div class="mt-1 flex flex-wrap gap-1">${message.reactions
    .map(r => {
      const mine = r.user_ids.includes(me.id)
      return `<button type="button" data-action="toggle-reaction" data-message-id="${message.id}" data-emoji="${esc(r.emoji)}"
        title="${esc(r.user_ids.join(", "))}"
        class="inline-flex items-center gap-1 rounded-full border px-1.5 py-0.5 text-xs tabular-nums transition-all active:scale-95 ${mine ? "border-primary/40 bg-primary/10 text-primary" : "border-base-content/10 bg-base-content/5 hover:border-base-content/25"}">
        <span>${esc(r.emoji)}</span><span>${r.count}</span>
      </button>`
    })
    .join("")}</div>`
}

function ReactionPicker(message) {
  return `<div class="absolute -top-10 right-2 z-10 flex gap-0.5 rounded-full border border-base-content/10 bg-base-100 p-1 shadow-lg">
    ${QUICK_EMOJI.map(e => `<button type="button" data-action="pick-reaction" data-message-id="${message.id}" data-emoji="${e}" class="grid size-7 place-items-center rounded-full text-base transition-transform hover:scale-125 hover:bg-base-content/5">${e}</button>`).join("")}
  </div>`
}

function Message(message, {me, grouped, pickerFor}) {
  const mine = message.sender.id === me.id
  const pending = !message.id
  const key = message.id || `pending-${message.client_ref}`
  const deleted = !!message.deleted_at

  const actions =
    pending || deleted
      ? ""
      : `<div class="absolute -top-3 right-2 hidden items-center gap-0.5 rounded-lg border border-base-content/10 bg-base-100 p-0.5 shadow-sm group-hover:flex">
        <button type="button" data-action="open-picker" data-message-id="${message.id}" class="rounded-md px-1.5 py-1 text-xs hover:bg-base-content/5" title="React">😊</button>
        <button type="button" data-action="reply" data-message-id="${message.id}" class="rounded-md px-1.5 py-1 text-xs hover:bg-base-content/5" title="Reply">↩︎</button>
        ${mine ? `<button type="button" data-action="edit" data-message-id="${message.id}" class="rounded-md px-1.5 py-1 text-xs hover:bg-base-content/5" title="Edit">✎</button>
        <button type="button" data-action="delete" data-message-id="${message.id}" class="rounded-md px-1.5 py-1 text-xs text-error hover:bg-error/10" title="Delete">🗑</button>` : ""}
      </div>`

  const status = pending
    ? message.status === "failed"
      ? `<span class="ml-1 text-xs text-error">Not sent${message.error ? ` (${esc(message.error)})` : ""} ·
          <button type="button" data-action="retry" data-client-ref="${esc(message.client_ref)}" class="font-medium underline">Retry</button> ·
          <button type="button" data-action="discard" data-client-ref="${esc(message.client_ref)}" class="font-medium underline">Discard</button></span>`
      : `<span class="ml-1 text-xs text-base-content/40">Sending…</span>`
    : ""

  const body = deleted
    ? `<p class="text-sm italic text-base-content/40">This message was deleted</p>`
    : `<p class="whitespace-pre-wrap break-words text-sm leading-relaxed ${pending ? "text-base-content/60" : ""}">${esc(message.text)}${message.edited_at ? `<span class="ml-1 text-[11px] text-base-content/40">(edited)</span>` : ""}${status}</p>`

  return `<li data-key="${key}" class="group relative flex gap-3 rounded-lg px-4 ${grouped ? "py-0.5" : "pt-2 pb-0.5"} transition-colors hover:bg-base-content/[0.03]">
    <div class="w-9 shrink-0">${grouped ? `<span class="hidden pt-1 text-[10px] tabular-nums text-base-content/40 group-hover:block">${esc(time(message.inserted_at))}</span>` : Avatar(message.sender)}</div>
    <div class="min-w-0 flex-1">
      ${grouped ? "" : `<p class="flex items-baseline gap-2"><span class="text-sm font-semibold">${esc(message.sender.display_name)}</span><time class="text-[11px] tabular-nums text-base-content/40">${esc(time(message.inserted_at))}</time></p>`}
      ${deleted ? "" : ReplyPreview(message.reply_to)}
      ${body}
      ${deleted ? "" : ReactionList(message, me)}
    </div>
    ${actions}
    ${pickerFor === message.id ? ReactionPicker(message) : ""}
  </li>`
}

function MessageList(messages, ctx) {
  if (messages.length === 0) {
    return `<li class="px-4 py-16 text-center text-sm text-base-content/50">No messages yet. Say hi 👋</li>`
  }
  let previous = null
  return messages
    .map(message => {
      const grouped =
        previous &&
        !previous.deleted_at &&
        !message.reply_to &&
        previous.sender.id === message.sender.id &&
        new Date(message.inserted_at) - new Date(previous.inserted_at) < GROUP_WINDOW_MS
      previous = message
      return Message(message, {...ctx, grouped})
    })
    .join("")
}

function TypingIndicator(label) {
  if (!label) return ""
  return `<span class="inline-flex items-center gap-1.5">
    <span class="flex gap-0.5"><span class="size-1 animate-bounce rounded-full bg-base-content/40"></span><span class="size-1 animate-bounce rounded-full bg-base-content/40 [animation-delay:150ms]"></span><span class="size-1 animate-bounce rounded-full bg-base-content/40 [animation-delay:300ms]"></span></span>
    ${esc(label)}
  </span>`
}

function ComposerContext({replyTo, editing}) {
  if (editing) {
    return `<div class="flex items-center gap-2 px-1 pb-2 text-xs text-base-content/60">
      <span class="font-medium text-primary">Editing message</span>
      <button type="button" data-action="cancel-compose" class="ml-auto rounded px-1.5 py-0.5 hover:bg-base-content/5">Cancel · Esc</button>
    </div>`
  }
  if (replyTo) {
    return `<div class="flex items-center gap-2 px-1 pb-2">
      <span class="text-xs text-base-content/50">Replying to</span>
      <div class="min-w-0 flex-1">${ReplyPreview({sender: replyTo.sender, text: replyTo.text, deleted: false}, {compact: false})}</div>
      <button type="button" data-action="cancel-compose" class="rounded px-1.5 py-0.5 text-xs text-base-content/60 hover:bg-base-content/5">✕</button>
    </div>`
  }
  return ""
}

function Composer() {
  return `<form data-ref="composer" class="border-t border-base-content/10 px-3 pt-2 pb-3">
    <div data-ref="composer-context"></div>
    <div class="flex items-end gap-2 rounded-xl border border-base-content/15 bg-base-100 px-3 py-2 transition-colors focus-within:border-primary/50 focus-within:ring-2 focus-within:ring-primary/15">
      <textarea data-ref="input" rows="1" placeholder="Write a message…"
        class="max-h-40 min-h-6 flex-1 resize-none bg-transparent text-sm outline-none placeholder:text-base-content/40"></textarea>
      <button type="submit" class="rounded-lg bg-primary px-3 py-1.5 text-xs font-semibold text-primary-content shadow-sm transition-all hover:brightness-110 active:scale-95 disabled:opacity-40">Send</button>
    </div>
    <p class="mt-1 px-1 text-[11px] text-base-content/40">Enter to send · Shift+Enter for a new line</p>
  </form>`
}

function ChatLayout() {
  return `<div class="flex h-[70vh] min-h-[30rem] overflow-hidden rounded-2xl border border-base-content/10 bg-base-100 shadow-sm">
    <aside data-ref="list-pane" class="flex w-full shrink-0 flex-col border-r border-base-content/10 md:w-72">
      <div class="flex items-center gap-2 border-b border-base-content/10 px-4 py-3">
        <span class="font-semibold">Conversations</span>
        <span data-ref="connection" class="ml-auto flex items-center gap-1.5 text-[11px] text-base-content/50"></span>
      </div>
      <ul data-ref="rooms" class="flex-1 space-y-0.5 overflow-y-auto p-2"></ul>
    </aside>
    <section data-ref="room-pane" class="hidden min-w-0 flex-1 flex-col md:flex">
      <div data-ref="empty" class="grid flex-1 place-items-center p-6 text-center text-sm text-base-content/50">
        <div><div class="mb-2 text-3xl">💬</div>Pick a conversation</div>
      </div>
      <div data-ref="room" class="hidden min-h-0 flex-1 flex-col">
        <div data-ref="header"></div>
        <div data-ref="scroller" class="min-h-0 flex-1 overflow-y-auto py-2">
          <div data-ref="older" class="hidden px-4 pb-2 text-center">
            <button type="button" data-action="load-older" class="rounded-full border border-base-content/10 px-3 py-1 text-xs text-base-content/60 hover:bg-base-content/5">Load older messages</button>
          </div>
          <ol data-ref="messages"></ol>
        </div>
        <div data-ref="typing" class="h-5 px-4 text-xs text-base-content/50"></div>
        ${Composer()}
      </div>
    </section>
  </div>`
}

// ---- The hook ----

export const ChatDemo = {
  mounted() {
    this.el.innerHTML = ChatLayout()
    this.ref = name => this.el.querySelector(`[data-ref="${name}"]`)
    this.state = {replyTo: null, editing: null, pickerFor: null, renderLimit: RENDER_LIMIT}
    this.room = null
    // Listeners for the whole page, and for the open room only.
    this.unsubscribe = []
    this.roomSubs = []

    this.chat = new Chat({
      url: this.el.dataset.socketUrl,
      getToken: () =>
        new Promise((resolve, reject) =>
          this.pushEvent("token", {}, reply => (reply.error ? reject(new Error(reply.error)) : resolve(reply))),
        ),
    })

    this.chat.on("connection", () => this.renderConnection())
    this.chat.rooms.on("change", () => this.renderRooms())
    this.chat.connect().then(() => this.renderConnection()).catch(error => {
      this.ref("rooms").innerHTML = `<li class="px-3 py-6 text-center text-sm text-error">Couldn't connect: ${esc(error.message)}</li>`
    })

    this.bindEvents()
  },

  destroyed() {
    this.roomSubs.forEach(off => off())
    this.unsubscribe.forEach(off => off())
    this.chat?.disconnect()
  },

  bindEvents() {
    this.el.addEventListener("click", e => {
      const target = e.target.closest("[data-action]")
      if (!target && this.state.pickerFor) return this.setState({pickerFor: null})
      if (!target) return
      this.handleAction(target.dataset.action, target.dataset)
    })

    const input = this.ref("input")
    input.addEventListener("input", () => {
      input.style.height = "auto"
      input.style.height = `${input.scrollHeight}px`
      if (!this.state.editing && input.value.trim()) this.room?.typing.keystroke()
    })
    input.addEventListener("keydown", e => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        this.submit()
      } else if (e.key === "Escape") {
        this.cancelCompose()
      } else if (e.key === "ArrowUp" && !input.value) {
        // Edit your last message, as in Slack.
        const mine = this.room?.messages.list().filter(m => m.id && !m.deleted_at && m.sender.id === this.chat.user.id)
        if (mine?.length) this.startEdit(mine[mine.length - 1].id)
      }
    })
    this.ref("composer").addEventListener("submit", e => {
      e.preventDefault()
      this.submit()
    })

    this.ref("scroller").addEventListener("scroll", () => this.maybeMarkRead())
    this.onVisibility = () => this.maybeMarkRead()
    document.addEventListener("visibilitychange", this.onVisibility)
    this.unsubscribe.push(() => document.removeEventListener("visibilitychange", this.onVisibility))
  },

  handleAction(action, data) {
    const id = Number(data.messageId)
    switch (action) {
      case "open-room":
        return this.openRoom(Number(data.roomId))
      case "back":
        return this.showList()
      case "load-older":
        return this.loadOlder()
      case "open-picker":
        return this.setState({pickerFor: this.state.pickerFor === id ? null : id})
      case "pick-reaction":
        this.setState({pickerFor: null})
        return this.room.toggleReaction(id, data.emoji).catch(() => {})
      case "toggle-reaction":
        return this.room.toggleReaction(id, data.emoji).catch(() => {})
      case "reply":
        return this.startReply(id)
      case "edit":
        return this.startEdit(id)
      case "delete":
        if (confirm("Delete this message for everyone?")) this.room.delete(id).catch(() => {})
        return
      case "retry":
        return this.room.retry(data.clientRef)
      case "discard":
        return this.room.discard(data.clientRef)
      case "cancel-compose":
        return this.cancelCompose()
    }
  },

  async openRoom(id) {
    if (this.room?.id === id) return this.showRoom()
    this.roomSubs.forEach(off => off())
    this.roomSubs = []
    this.room?.detach()
    this.cancelCompose()
    this.state.renderLimit = RENDER_LIMIT

    const room = this.chat.room(id)
    this.room = room
    this.stickToBottom = true
    this.ref("empty").classList.add("hidden")
    this.ref("room").classList.replace("hidden", "flex")
    this.ref("messages").innerHTML = `<li class="px-4 py-16 text-center text-sm text-base-content/40">Loading…</li>`
    this.renderRooms()
    this.showRoom()

    this.roomSubs.push(
      room.messages.on("change", () => this.renderMessages()),
      room.typing.on("change", () => this.renderTyping()),
      room.presence.on("change", () => this.renderHeader()),
      room.on("members", () => this.renderHeader()),
      room.on("status", () => this.renderHeader()),
    )

    try {
      await room.attach()
      this.renderHeader()
      this.ref("input").focus()
    } catch (error) {
      this.ref("messages").innerHTML = `<li class="px-4 py-16 text-center text-sm text-error">Couldn't open this room (${esc(error.message)}).</li>`
    }
  },

  showRoom() {
    this.ref("list-pane").classList.add("hidden", "md:flex")
    this.ref("room-pane").classList.remove("hidden")
    this.ref("room-pane").classList.add("flex")
  },

  showList() {
    this.ref("list-pane").classList.remove("hidden", "md:flex")
    this.ref("room-pane").classList.add("hidden")
    this.ref("room-pane").classList.remove("flex")
  },

  submit() {
    const input = this.ref("input")
    const text = input.value.trim()
    if (!text || !this.room) return

    if (this.state.editing) {
      this.room.edit(this.state.editing, text).catch(() => {})
    } else {
      this.room.send(text, {replyTo: this.state.replyTo?.id})
      this.stickToBottom = true
    }

    input.value = ""
    input.style.height = "auto"
    this.cancelCompose()
  },

  startReply(id) {
    const message = this.room.messages.list().find(m => m.id === id)
    if (!message) return
    this.state.editing = null
    this.state.replyTo = message
    this.renderComposerContext()
    this.ref("input").focus()
  },

  startEdit(id) {
    const message = this.room.messages.list().find(m => m.id === id)
    if (!message) return
    this.state.replyTo = null
    this.state.editing = id
    const input = this.ref("input")
    input.value = message.text
    input.focus()
    input.setSelectionRange(input.value.length, input.value.length)
    this.renderComposerContext()
  },

  cancelCompose() {
    if (this.state.editing) this.ref("input").value = ""
    this.state.replyTo = null
    this.state.editing = null
    this.renderComposerContext()
  },

  async loadOlder() {
    const scroller = this.ref("scroller")
    const before = scroller.scrollHeight
    this.state.renderLimit += 50
    await this.room.loadOlder()
    // Keep the view where it was instead of jumping.
    scroller.scrollTop += scroller.scrollHeight - before
  },

  setState(patch) {
    Object.assign(this.state, patch)
    this.renderMessages()
  },

  isAtBottom() {
    const s = this.ref("scroller")
    return s.scrollHeight - s.scrollTop - s.clientHeight < 40
  },

  maybeMarkRead() {
    if (this.room && document.visibilityState === "visible" && this.isAtBottom()) this.room.markRead()
  },

  renderConnection() {
    const connected = this.chat.connection === "connected"
    this.ref("connection").innerHTML = `<span class="size-1.5 rounded-full ${connected ? "bg-success" : "bg-warning animate-pulse"}"></span>${connected ? esc(this.chat.user?.display_name || "Connected") : "Connecting…"}`
  },

  renderRooms() {
    if (!this.chat.user) return
    this.ref("rooms").innerHTML = RoomList(this.chat.rooms.list(), {me: this.chat.user, activeId: this.room?.id})
  },

  renderHeader() {
    const room = this.room
    if (!room?.info) return
    const summary = {...room.info, members: room.members}
    this.ref("header").innerHTML = ChatHeader(summary, {
      me: this.chat.user,
      online: room.presence.list(),
      status: room.status,
    })
  },

  renderMessages() {
    if (!this.room) return
    const scroller = this.ref("scroller")
    const stick = this.stickToBottom || this.isAtBottom()
    const all = this.room.messages.list()
    const shown = all.slice(-this.state.renderLimit)

    this.ref("older").classList.toggle("hidden", !(this.room.hasMore || shown.length < all.length))
    this.ref("messages").innerHTML = MessageList(shown, {me: this.chat.user, pickerFor: this.state.pickerFor})

    if (stick) scroller.scrollTop = scroller.scrollHeight
    this.stickToBottom = false
    this.maybeMarkRead()
  },

  renderTyping() {
    this.ref("typing").innerHTML = TypingIndicator(this.room.typing.label())
  },

  renderComposerContext() {
    this.ref("composer-context").innerHTML = ComposerContext(this.state)
  },
}
