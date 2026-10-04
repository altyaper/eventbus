// Pure state helpers for the chat SDK: no sockets, no DOM. Messages are kept
// in a Map keyed by id (or by `pending:<client_ref>` until the server has
// stored them), so applying the same event twice changes nothing.

export const pendingKey = clientRef => `pending:${clientRef}`

// How far along a message snapshot is: a deleted one beats an edited one,
// which beats the original, so a late, older snapshot can't undo a change.
const progress = m => [m.deleted_at ? 1 : 0, m.edited_at || ""]

const isNewer = (a, b) => {
  const [ad, ae] = progress(a)
  const [bd, be] = progress(b)
  return ad !== bd ? ad > bd : ae >= be
}

// Inserts or updates a server message, replacing its pending copy if this
// is the message we sent optimistically.
export function upsertMessage(messages, message) {
  if (message.client_ref) messages.delete(pendingKey(message.client_ref))
  const existing = messages.get(message.id)
  if (!existing || isNewer(message, existing)) messages.set(message.id, message)
  return messages
}

// Chronological order: stored messages by id, then pending ones in the order
// they were sent.
export function sortedMessages(messages) {
  const stored = []
  const pending = []
  for (const m of messages.values()) (m.id ? stored : pending).push(m)
  stored.sort((a, b) => a.id - b.id)
  pending.sort((a, b) => a.sent_at - b.sent_at)
  return stored.concat(pending)
}

export function newestId(messages) {
  let newest = null
  for (const m of messages.values()) if (m.id && (newest === null || m.id > newest)) newest = m.id
  return newest
}

export function oldestId(messages) {
  let oldest = null
  for (const m of messages.values()) if (m.id && (oldest === null || m.id < oldest)) oldest = m.id
  return oldest
}

// Applies a chat.reaction.added / removed event to a message's aggregated
// `[{emoji, count, user_ids}]`.
export function applyReaction(message, {emoji, user_id}, added) {
  const reactions = message.reactions.map(r => ({...r, user_ids: [...r.user_ids]}))
  let entry = reactions.find(r => r.emoji === emoji)

  if (added) {
    if (!entry) reactions.push((entry = {emoji, count: 0, user_ids: []}))
    if (!entry.user_ids.includes(user_id)) entry.user_ids.push(user_id)
  } else if (entry) {
    entry.user_ids = entry.user_ids.filter(id => id !== user_id)
  }

  for (const r of reactions) r.count = r.user_ids.length
  return {...message, reactions: reactions.filter(r => r.count > 0)}
}

// "Ann is typing…", "Ann and Bo are typing…", "Several people are typing…"
export function typingLabel(names) {
  if (names.length === 0) return ""
  if (names.length === 1) return `${names[0]} is typing…`
  if (names.length === 2) return `${names[0]} and ${names[1]} are typing…`
  return "Several people are typing…"
}

// Room list order: latest activity first. Timestamps are parsed, not
// compared as strings: rooms carry second-precision times and messages
// microsecond ones, and "…32Z" sorts after "…32.5Z" as text.
export function sortRooms(rooms) {
  const at = r => Date.parse(r.last_message_at || r.inserted_at || 0) || 0
  return [...rooms].sort((a, b) => at(b) - at(a) || b.id - a.id)
}

export function makeClientRef() {
  return globalThis.crypto?.randomUUID
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`
}
