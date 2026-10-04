// eventbus chat SDK: rooms, messages, typing, presence and unread counts on
// eventbus's Phoenix Channels. Headless: it holds state and emits "change"
// events; rendering is up to the app.
//
//   const chat = new Chat({url: "https://eventbus.example/socket",
//                          getToken: () => fetch("/chat-token").then(r => r.json())})
//   await chat.connect()
//   chat.rooms.on("change", rooms => ...)
//   const room = await chat.room(roomId).attach()
//   room.messages.on("change", messages => ...)
//   room.send("hi")
//
// `getToken` returns what your backend got from `POST /api/chat/tokens`:
// `{token, expires_at, user, app}`. It's called again before the token
// expires, so keep your backend endpoint available.

import {Socket} from "phoenix"
import {Emitter} from "./emitter"
import {Room} from "./room"
import {sortRooms, typingLabel} from "./state"

const REFRESH_BEFORE_EXPIRY_MS = 60_000
const REFRESH_RETRY_MS = 10_000

export class Chat extends Emitter {
  constructor({url = "/socket", getToken, socketOptions = {}}) {
    super()
    if (typeof getToken !== "function") throw new Error("Chat needs a getToken function")
    this.url = url
    this.getToken = getToken
    this.socketOptions = socketOptions
    this.user = null
    this.app = null
    this.connection = "disconnected"
    this.rooms = new RoomList(this)
    this._rooms = new Map()
  }

  async connect() {
    await this._refreshToken()

    this.socket = new Socket(this.url, {...this.socketOptions, params: () => ({token: this._token})})
    this.socket.onOpen(() => this._setConnection("connected"))
    this.socket.onClose(() => this._setConnection("disconnected"))
    // A token that expired while the page slept gets refused; fetch a new
    // one so the next reconnect attempt can succeed.
    this.socket.onError(() => {
      if (Date.now() > this._expiresAt - REFRESH_BEFORE_EXPIRY_MS) this._refreshToken().catch(() => {})
    })
    this.socket.connect()

    await this.rooms._join()
    return this
  }

  disconnect() {
    clearTimeout(this._refreshTimer)
    for (const room of [...this._rooms.values()]) room.detach()
    this.rooms._leave()
    this.socket?.disconnect()
  }

  // The room with `id`, created on first use; call `attach()` to join it.
  room(id) {
    id = Number(id)
    if (!this._rooms.has(id)) this._rooms.set(id, new Room(this, id))
    return this._rooms.get(id)
  }

  _roomDetached(room) {
    this._rooms.delete(room.id)
  }

  _refreshToken() {
    if (this._refreshing) return this._refreshing

    this._refreshing = Promise.resolve(this.getToken())
      .then(({token, expires_at, user, app}) => {
        this._token = token
        this._expiresAt = Date.parse(expires_at)
        this.user = user
        this.app = app
        this._scheduleRefresh(this._expiresAt - Date.now() - REFRESH_BEFORE_EXPIRY_MS)
      })
      .catch(error => {
        this._scheduleRefresh(REFRESH_RETRY_MS)
        throw error
      })
      .finally(() => (this._refreshing = null))

    return this._refreshing
  }

  _scheduleRefresh(ms) {
    clearTimeout(this._refreshTimer)
    this._refreshTimer = setTimeout(() => this._refreshToken().catch(() => {}), Math.max(ms, 5_000))
  }

  _setConnection(state) {
    if (this.connection === state) return
    this.connection = state
    this.emit("connection", state)
  }
}

// The current user's rooms for a sidebar, kept up to date from their own
// channel: latest message, unread count, joins and removals. `list()` is
// sorted by latest activity; "change" fires with that list.
export class RoomList extends Emitter {
  constructor(chat) {
    super()
    this.chat = chat
    this._rooms = new Map()
  }

  list() {
    return sortRooms([...this._rooms.values()])
  }

  get(id) {
    return this._rooms.get(Number(id))
  }

  _join() {
    const {app, user} = this.chat
    this.channel = this.chat.socket.channel(`chat_user:${app}:${user.id}`)

    this.channel.on("room.activity", ({room_id, message, last_message_at}) => {
      const room = this._rooms.get(room_id)
      if (!room) return
      const open = this.chat._rooms.get(room_id)?.status === "attached"
      const fromOthers = message.sender.id !== this.chat.user.id
      this._put({
        ...room,
        last_message: message,
        last_message_at,
        unread_count: room.unread_count + (fromOthers && !open ? 1 : 0),
      })
    })

    this.channel.on("read_state.updated", ({room_id, unread_count}) => {
      const room = this._rooms.get(room_id)
      if (room) this._put({...room, unread_count})
    })

    this.channel.on("room.member.added", ({room}) => {
      if (!this._rooms.has(room.id)) this._put({last_message: null, members: [], unread_count: 0, ...room})
    })

    this.channel.on("room.member.removed", ({room_id}) => {
      this._rooms.delete(room_id)
      this.emit("change", this.list())
    })

    return new Promise((resolve, reject) => {
      this.channel
        .join()
        // Every (re)join brings the full list, so counts are fresh after a
        // reconnect.
        .receive("ok", ({rooms}) => {
          this._rooms = new Map(rooms.map(r => [r.id, r]))
          this.emit("change", this.list())
          resolve(this)
        })
        .receive("error", ({reason}) => reject(new Error(reason)))
    })
  }

  _leave() {
    this.channel?.leave()
  }

  _put(room) {
    this._rooms.set(room.id, room)
    this.emit("change", this.list())
  }

  _markedRead(roomId) {
    const room = this._rooms.get(roomId)
    if (room && room.unread_count) this._put({...room, unread_count: 0})
  }
}

// What to call a room in a list: its name, or for a direct room the other
// person's name.
export function roomTitle(room, me) {
  if (room.type !== "direct") return room.name
  const other = room.members.find(m => m.user.id !== me?.id)
  return other ? other.user.display_name : "Direct message"
}

export {Room, typingLabel}
