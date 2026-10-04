import {Presence} from "phoenix"
import {Emitter} from "./emitter"
import {
  applyReaction,
  makeClientRef,
  newestId,
  oldestId,
  pendingKey,
  sortedMessages,
  typingLabel,
  upsertMessage,
} from "./state"

// Typing: tell the room at most this often while keys are pressed, stop
// after this long without one, and forget a remote typist this long after
// their last "started".
const TYPING_REFRESH_MS = 2000
const TYPING_IDLE_MS = 3000
const TYPING_REMOTE_TTL_MS = 5000
const READ_DEBOUNCE_MS = 1000
const PAGE_SIZE = 50

// One chat room: join it with `attach()`, then read state from
// `room.messages`, `room.typing` and `room.presence` (each emits "change")
// and write with `send`, `edit`, `delete`, `react`, ... Headless: rendering
// is up to the app.
export class Room extends Emitter {
  constructor(chat, id) {
    super()
    this.chat = chat
    this.id = id
    this.info = null
    this.members = []
    this.hasMore = false
    this.lastReadId = null
    this.status = "detached"
    this._messages = new Map()
    this._typists = new Map()
    this._typingSentAt = null
    this._typingIdleTimer = null
    this._readTimer = null
    this._joined = false

    this.messages = new Emitter()
    this.messages.list = () => sortedMessages(this._messages)

    this.typing = new Emitter()
    this.typing.users = () => [...this._typists.values()].map(t => t.user)
    this.typing.label = () => typingLabel(this.typing.users().map(u => u.display_name))
    this.typing.keystroke = () => this._keystroke()
    this.typing.stop = () => this._stopTyping(true)

    this.presence = new Emitter()
    this.presence.list = () => (this._presence ? this._presenceList() : [])
  }

  get topic() {
    return `chat:${this.chat.app}:${this.id}`
  }

  // Joins the room. Resolves with the room once the first join succeeds;
  // after that phoenix.js rejoins by itself, asking only for the messages
  // missed meanwhile.
  attach() {
    if (this._attaching) return this._attaching

    this.channel = this.chat.socket.channel(this.topic, () => {
      const after = newestId(this._messages)
      return after ? {after} : {}
    })

    this._presence = new Presence(this.channel)
    this._presence.onSync(() => this.presence.emit("change", this.presence.list()))

    this._bind()
    this._setStatus("attaching")

    this._attaching = new Promise((resolve, reject) => {
      this.channel
        .join()
        .receive("ok", reply => {
          const rejoin = this._joined
          this._joined = true
          this._applyJoin(reply, rejoin)
          this._setStatus("attached")
          if (rejoin) this._resendPending()
          resolve(this)
        })
        .receive("error", ({reason}) => {
          this._setStatus("failed")
          this.emit("error", {reason})
          // A rejected first join won't succeed by retrying.
          if (!this._joined) {
            this.channel.leave()
            this._attaching = null
          }
          reject(new Error(reason))
        })
    })

    return this._attaching
  }

  detach() {
    this._stopTyping(true)
    clearTimeout(this._readTimer)
    for (const t of this._typists.values()) clearTimeout(t.timer)
    this._typists.clear()
    if (this.channel) this.channel.leave()
    this.channel = null
    this._attaching = null
    this._joined = false
    this._setStatus("detached")
    this.chat._roomDetached(this)
  }

  // Sends a message optimistically: it appears at once as pending, then is
  // replaced by the stored one (from the reply or the broadcast, whichever
  // comes first). A failed send stays, marked failed, for `retry`.
  send(text, {replyTo = null, metadata = undefined} = {}) {
    const clientRef = makeClientRef()
    const replied = replyTo ? this._messages.get(replyTo) : null

    this._messages.set(pendingKey(clientRef), {
      id: null,
      client_ref: clientRef,
      room_id: this.id,
      sender: this.chat.user,
      text: text.trim(),
      metadata: metadata || {},
      reply_to: replied
        ? {id: replied.id, sender: replied.sender, text: replied.text.slice(0, 140), deleted: false}
        : null,
      reply_to_id: replyTo,
      reactions: [],
      edited_at: null,
      deleted_at: null,
      inserted_at: new Date().toISOString(),
      sent_at: Date.now(),
      status: "sending",
      error: null,
    })

    // The server stops our typing when the message arrives.
    this._stopTyping(false)
    this._changed()
    this._pushPending(clientRef)
    return clientRef
  }

  retry(clientRef) {
    const pending = this._messages.get(pendingKey(clientRef))
    if (!pending) return
    this._messages.set(pendingKey(clientRef), {...pending, status: "sending", error: null})
    this._changed()
    this._pushPending(clientRef)
  }

  // Drops a failed message instead of retrying it.
  discard(clientRef) {
    if (this._messages.delete(pendingKey(clientRef))) this._changed()
  }

  edit(id, text) {
    return this._request("message:edit", {id, text}).then(({message}) => this._upsert(message))
  }

  delete(id) {
    return this._request("message:delete", {id}).then(({message}) => this._upsert(message))
  }

  react(messageId, emoji) {
    return this._request("reaction:add", {message_id: messageId, emoji})
  }

  unreact(messageId, emoji) {
    return this._request("reaction:remove", {message_id: messageId, emoji})
  }

  // Toggles the current user's `emoji` on a message.
  toggleReaction(messageId, emoji) {
    const message = this._messages.get(messageId)
    const mine = message?.reactions.find(r => r.emoji === emoji)?.user_ids.includes(this.chat.user.id)
    return mine ? this.unreact(messageId, emoji) : this.react(messageId, emoji)
  }

  // Loads the page before the oldest message held.
  loadOlder() {
    const before = oldestId(this._messages)
    if (!before || !this.hasMore) return Promise.resolve([])

    return this._request("history", {before, limit: PAGE_SIZE}).then(({messages, has_more}) => {
      for (const m of messages) upsertMessage(this._messages, m)
      this.hasMore = has_more
      this._changed()
      return messages
    })
  }

  // Marks everything up to the newest message read, at most once a second
  // and only when that message changed. Call it while the room is visible
  // and its newest message is in view.
  markRead() {
    clearTimeout(this._readTimer)
    this._readTimer = setTimeout(() => {
      const newest = newestId(this._messages)
      if (!newest || (this.lastReadId && newest <= this.lastReadId)) return
      this.lastReadId = newest
      this._request("read", {message_id: newest}).catch(() => {})
      this.chat.rooms._markedRead(this.id)
    }, READ_DEBOUNCE_MS)
  }

  _bind() {
    const on = (event, fn) => this.channel.on(event, fn)

    on("chat.message.created", ({message}) => this._upsert(message))
    on("chat.message.updated", ({message}) => this._upsert(message))
    on("chat.message.deleted", ({message}) => this._upsert(message))

    const reaction = added => payload => {
      const message = this._messages.get(payload.message_id)
      if (!message) return
      this._messages.set(message.id, applyReaction(message, payload, added))
      this._changed()
    }
    on("chat.reaction.added", reaction(true))
    on("chat.reaction.removed", reaction(false))

    on("chat.typing.started", ({user_id}) => this._remoteTyping(user_id, true))
    on("chat.typing.stopped", ({user_id}) => this._remoteTyping(user_id, false))

    on("chat.member.joined", ({member}) => {
      this.members = this.members.filter(m => m.user.id !== member.user.id).concat([member])
      this.emit("members", this.members)
    })
    on("chat.member.left", ({member}) => {
      this.members = this.members.filter(m => m.user.id !== member.user.id)
      this.emit("members", this.members)
    })

    // The server closes the channel when we're removed from the room.
    this.channel.onClose(() => {
      if (this.status !== "detached") {
        this._setStatus("removed")
        this.emit("removed")
      }
    })
    this.channel.onError(() => {
      if (this._joined) this._setStatus("reconnecting")
    })
  }

  _applyJoin(reply, rejoin) {
    this.info = reply.room
    this.members = reply.members
    this.lastReadId = reply.read_state.last_read_message_id

    // A gap too long to fill: start over from the newest page, keeping only
    // messages we're still sending.
    if (reply.gap_truncated) {
      for (const [key, m] of this._messages) if (m.id) this._messages.delete(key)
    }

    for (const m of reply.messages) upsertMessage(this._messages, m)
    // A rejoin's reply is the gap after our newest message; it says nothing
    // about older history.
    if (!rejoin || reply.gap_truncated) this.hasMore = reply.has_more

    this.emit("members", this.members)
    this._changed()
  }

  _pushPending(clientRef) {
    const pending = this._messages.get(pendingKey(clientRef))
    const payload = {text: pending.text, client_ref: clientRef}
    if (pending.reply_to_id) payload.reply_to_id = pending.reply_to_id
    if (Object.keys(pending.metadata).length) payload.metadata = pending.metadata

    this._request("message:send", payload)
      .then(({message}) => this._upsert(message))
      .catch(error => {
        const current = this._messages.get(pendingKey(clientRef))
        if (!current) return
        this._messages.set(pendingKey(clientRef), {...current, status: "failed", error: error.reason})
        this._changed()
      })
  }

  // After a reconnect, sends again whatever didn't get through. The server
  // dedupes by client_ref, so a send that did arrive isn't stored twice.
  _resendPending() {
    for (const m of this._messages.values()) {
      if (!m.id && (m.status === "sending" || m.error === "timeout")) this.retry(m.client_ref)
    }
  }

  _request(event, payload) {
    return new Promise((resolve, reject) => {
      if (!this.channel) return reject({reason: "detached"})

      this.channel
        .push(event, payload)
        .receive("ok", reply => resolve(reply || {}))
        .receive("error", error => reject(error))
        .receive("timeout", () => reject({reason: "timeout"}))
    })
  }

  _upsert(message) {
    upsertMessage(this._messages, message)
    this._changed()
    return message
  }

  _changed() {
    this.messages.emit("change", this.messages.list())
  }

  _setStatus(status) {
    this.status = status
    this.emit("status", status)
  }

  _keystroke() {
    const now = Date.now()
    if (!this._typingSentAt || now - this._typingSentAt >= TYPING_REFRESH_MS) {
      this._typingSentAt = now
      this.channel?.push("typing", {typing: true})
    }
    clearTimeout(this._typingIdleTimer)
    this._typingIdleTimer = setTimeout(() => this._stopTyping(true), TYPING_IDLE_MS)
  }

  _stopTyping(notify) {
    clearTimeout(this._typingIdleTimer)
    if (this._typingSentAt && notify) this.channel?.push("typing", {typing: false})
    this._typingSentAt = null
  }

  _remoteTyping(userId, typing) {
    // Our own other tabs.
    if (userId === this.chat.user.id) return

    const existing = this._typists.get(userId)
    if (existing) clearTimeout(existing.timer)

    if (typing) {
      const member = this.members.find(m => m.user.id === userId)
      const user = member ? member.user : {id: userId, display_name: userId}
      const timer = setTimeout(() => this._remoteTyping(userId, false), TYPING_REMOTE_TTL_MS)
      this._typists.set(userId, {user, timer})
    } else {
      this._typists.delete(userId)
    }

    this.typing.emit("change", this.typing.users())
  }

  _presenceList() {
    return this._presence.list((id, {metas}) => ({
      id,
      display_name: metas[0].display_name,
      avatar_url: metas[0].avatar_url,
      connections: metas.length,
    }))
  }
}
