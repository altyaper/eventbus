# Chat design

An Ably Chat-style chat layer that consuming applications (changologs, etc.) use for their own
end users: rooms, messages, history, replies, edit/delete, reactions, typing, presence and unread
counts. Built on the existing Phoenix Channels + `Phoenix.PubSub`; the topic publish/listen path
(`POST /api/topics/:name/events`, `TopicChannel`, `Events.publish/2`) is unchanged.

## Decisions

- **General SDK, full feature list, four phases.** Rejected: scoping v1 to one changologs feature
  (there is no consumer yet).
- **Chat users belong to the consuming apps.** eventbus never authenticates them; an app's
  backend mints a short-lived user token with its client credentials (Ably token auth).
  Rejected: eventbus accounts for chat users.
- **Clients write over the WebSocket** (`handle_in` on the room channel, gated by the user
  token and membership). Rejected: app backends proxying every write over HTTP (latency, typing
  impractical). This is the first client write path since WS publish was removed.
- **Chat gets its own channel namespace**, not `topic:<slug>.*`: topic channels are readable by
  any allowed-origin socket, so private rooms would leak.
- **Membership lives in eventbus, managed by the app's backend over HTTP.** Rejected: Ably-style
  room capabilities in the token (revocation only at expiry, "member" means "has joined once"),
  and a hybrid of both (can be added later without a rewrite).
- **One room channel for the open room plus a per-user channel** for sidebar activity. Rejected:
  joining every room (typing/presence noise from all rooms) and polling the room list.
- **Browser reads go over the socket** (join replies and `history` pushes). Rejected: HTTP reads
  with a bearer user token (needs CORS driven by per-app origins, token handling twice). HTTP
  reads with app credentials wait for a consumer that needs them.
- **Typing state lives in each channel process**, not a shared ETS table: simpler, multi-node
  safe, and cleaned up when the socket dies.
- **The SDK is headless** (state + events, no rendering). The demo page's render functions are
  demo code, so apps can use React, LiveView or anything else.

## 1. Architecture and identity

- **`Eventbus.Chat.*` contexts** own persistence and authorization: `Users`, `Rooms`,
  `Messages`, `Reactions`, `ReadStates`. Public functions take a `%Chat.Caller{app, user}` (or
  just an `app` for server-side calls) and enforce the rules, so channels, HTTP API and admin
  LiveView share one code path, like `Events`.
- **`Eventbus.Chat.Broadcast`** is the only module calling `Phoenix.PubSub`, on
  `chat:<slug>:<room_id>` and `chat_user:<slug>:<user_id>`. Contexts return
  `{:ok, result, events}`; callers hand events to `Broadcast`.
- **Ephemeral:** `Chat.Presence` (`Phoenix.Presence`, added to the supervision tree) and typing
  in the room channel process.
- **Transport:** `ChatRoomChannel` and `ChatUserChannel` on the existing `UserSocket`, plus
  HTTP endpoints in the existing `:api` pipeline.
- **Clients:** JS SDK (`assets/js/chat/`), admin Chat section, demo page.

Identity:

- `POST /api/chat/tokens` (app Basic auth), body `{user_id, display_name, avatar_url?}`: upserts
  `chat_users`, returns `{token, expires_at}`, a `Phoenix.Token` of `{app_id, chat_user_id}`
  valid for 1 hour. The SDK takes a `getToken()` callback and refetches when expired.
- `UserSocket.connect/3`: no `token` → anonymous as today; valid → assigns `chat_user` and
  `chat_app`; invalid or expired → refused. `id/1` is `"chat_socket:<chat_user_id>"` for token
  sockets so they can be force-disconnected.
- Both chat channels require a token socket whose app matches the topic's slug, plus the per-app
  origin check from `Origins`. Anonymous sockets can't join them.
- Sender, presence and typing identity always come from `socket.assigns`, never payloads.

Server-side HTTP API (app Basic auth): create room, add/remove member (with role), send a
message as a given user (bots).

## 2. Data model

Bigserial ids, `:utc_datetime` timestamps, everything cascades from `applications`.

| Table | Columns | Constraints / indexes |
|---|---|---|
| `chat_users` | application_id, external_id, display_name, avatar_url | unique (application_id, external_id) |
| `chat_rooms` | application_id, name, type (direct/group/public), direct_key, created_by_id, last_message_id, last_message_at, timestamps | unique (application_id, direct_key); index (application_id, last_message_at) |
| `chat_room_members` | room_id, chat_user_id, role (member/moderator), joined_at | unique (room_id, chat_user_id); index (chat_user_id) |
| `chat_messages` | room_id, sender_id, text, metadata jsonb, reply_to_id, client_ref, edited_at, deleted_at, timestamps | index (room_id, id); unique (sender_id, client_ref) |
| `chat_message_reactions` | message_id, chat_user_id, emoji, inserted_at | unique (message_id, chat_user_id, emoji) |
| `chat_read_states` | room_id, chat_user_id, last_read_message_id, updated_at | unique (room_id, chat_user_id) |

- `direct_key` is `"<min user id>:<max user id>"`, so creating a direct room twice returns the
  existing one. Direct rooms have exactly two members and no name.
- `last_message_id` / `last_message_at` are updated in the same transaction as the message
  insert, so the sidebar sorts and previews with one join.
- `client_ref` is generated by the SDK per send; a repeat returns the existing message. Optional
  for server-side sends.
- Pagination is by message id over `(room_id, id)`: `before` for older, `after` for gap fill,
  pages oldest-first, `limit` ≤ 100.
- Unread = messages with `id > last_read_message_id`, not mine, not deleted; one grouped query
  for the room list, capped at 99 ("99+").
- Public rooms: a token user from the same app may join without membership, which inserts a
  `member` row. Direct and group rooms need a server-added membership.
- Delete sets `deleted_at`; text, metadata and reactions are blanked in serialization, the row
  stays. Removing a member deletes their membership and read state, not their messages.

## 3. Channels and event contract

**`ChatRoomChannel`**, `chat:<slug>:<room_id>`. Join: token socket of the same app, origin
allowed, member (or public room). Params `{after?}`. Reply
`{room, members, messages, read_state, has_more}`: newest page without `after`, everything since
it with `after` (`gap_truncated: true` past 100, and the SDK reloads). Tracks the user in
`Chat.Presence` after join.

Client pushes, replying `{:ok, …}` or `{:error, %{reason}}`:

| Event | Payload |
|---|---|
| `message:send` | `{text, client_ref, reply_to_id?, metadata?}` |
| `message:edit` | `{id, text}` |
| `message:delete` | `{id}` |
| `reaction:add` / `reaction:remove` | `{message_id, emoji}` |
| `typing` | `{typing: true \| false}` (no reply) |
| `read` | `{message_id}` |
| `history` | `{before, limit}` |

**`ChatUserChannel`**, `chat_user:<slug>:<user_id>`, own user only. Join reply is the room list
(preview, unread, members; the other user for direct rooms). Pushes: `room.activity`
`{room_id, message_preview, last_message_at}`, `room.member.added` / `room.member.removed`,
`read_state.updated` (clears badges in other tabs).

Room topic events:

| Event | Payload |
|---|---|
| `chat.message.created` / `.updated` / `.deleted` | `{room_id, message}` |
| `chat.reaction.added` / `.removed` | `{room_id, message_id, user_id, emoji}` |
| `chat.typing.started` / `.stopped` | `{room_id, user_id}` |
| `chat.member.joined` / `.left` | `{room_id, member}` |
| `presence_state` / `presence_diff` | Phoenix.Presence, keyed by chat_user_id |

- Presence metas are per connection (`{display_name, avatar_url, online_at}`), so a user is
  online while any tab is.
- `message` is always the full snapshot: `{id, room_id, sender, text, metadata, reply_to,
  client_ref, reactions: [{emoji, count, user_ids}], edited_at, deleted_at, inserted_at}`, with
  `reply_to` as `{id, sender_name, text excerpt, deleted}`. Applying an event twice is harmless.
- Typing: the channel process keeps its state in assigns with a `Process.send_after` timer.
  Repeated `true` within 3s doesn't rebroadcast; it expires 4s after the last refresh and the
  server broadcasts `stopped`; sending a message and `terminate/2` also stop it. Clients dedupe
  by user_id across tabs.

## 4. JS SDK

Plain ES modules in `assets/js/chat/`, depending only on `phoenix`, built as a separate esbuild
entry (`chat.js`) for other apps; the demo imports the same code.

```js
const chat = new Chat({url: "https://eventbus/socket", getToken: () => fetch("/my-backend/chat-token")…})
await chat.connect()
chat.rooms.on("change", list => …)          // sidebar: sorted rooms w/ preview + unread
const room = await chat.room(roomId).attach()
room.messages.on("change", msgs => …)       // chronological, deduped
room.send("hi", {replyTo})  room.edit(id, text)  room.delete(id)
room.react(id, "👍")  room.unreact(id, "👍")
room.typing.keystroke()   room.typing.on("change", users => …)
room.presence.on("change", members => …)
room.markRead()  room.loadOlder()  room.detach()
```

- **State:** a `Map` of messages by id per room; events are upserts; `change` emits a sorted
  array. Merge/dedupe/optimistic logic is pure functions.
- **Optimistic send:** generate `client_ref`, insert a pending message, reconcile on whichever
  arrives first (push reply or broadcast with the same `client_ref`). Error or timeout → `failed`;
  `room.retry(clientRef)` resends with the same `client_ref`.
- **Reconnect:** phoenix.js reconnects and rejoins; the SDK supplies rejoin params
  (`after: newest id`), merges the gap, refreshes an expired token first, and retries pending
  sends after rejoin.
- **Typing:** `keystroke()` sends `true` at most every 2s, `false` after 3s idle and on send;
  remote typers drop after 5s without refresh. A helper formats "Ann is typing…", "Ann and Bo
  are typing…", "Several people are typing…".
- **Read:** `markRead()` debounced 1s, only when the newest id changed. The demo calls it when
  the room is visible and the last message is in view (`IntersectionObserver`).
- **Unread:** incremented from `room.activity` when the room isn't attached and the sender isn't
  me; reset on `read_state.updated` and join replies.

README gains a "Chat" section: token endpoint, backend example, SDK quick start.

## 5. Admin UI and demo

**Chat section:** new `AppLive` `live_action` at `/apps/:slug/chat`, after Topics in the
section menu.

- Room list (stream): name or direct pair, type, member count, last activity; New room form
  (name, type).
- `/apps/:slug/chat/rooms/:id`: members (add by external id, remove, role) and message history
  newest-first with Load older; live via `Chat.Broadcast` topics, same event contract;
  moderation delete through the context as the app.
- Viewing for any logged-in user; create, members and delete are superadmin-only, like
  Credentials and Origins. `app_shell`, Tailwind, `app_components`, streams.

**Demo:** `/apps/:slug/chat/demo`, superadmin only.

- "Act as" form (external id, display name); the LiveView calls `Chat.Tokens.mint(app, attrs)`
  directly and passes the token to the hook. "Seed sample rooms" creates a group and a direct
  room with the user in both.
- A colocated hook element with `phx-update="ignore"` runs the SDK plus plain-JS render
  functions (`RoomList`, `ChatHeader`, `MessageList`, `Message`, `ReplyPreview`, `ReactionList`,
  `ReactionPicker`, `TypingIndicator`, `PresenceIndicator`, `Composer`): Slack-like two panes,
  unread badges, previews, online dots for direct rooms, sender grouping, edited/deleted states,
  hover actions, pending/failed sends, mobile list screen. Tailwind picks up classes through the
  existing `@source "../js"`.
- Two windows as different users is the end-to-end manual test.

Not in v1: list virtualization (pagination plus a DOM capped at ~500 messages instead), search,
attachments, push notifications, threads beyond one reply level, HTTP read APIs.

## 6. Errors, security, testing

Errors:

- Channel replies `{:error, %{reason}}` with `not_found | forbidden | invalid | rate_limited`;
  changeset errors as `{reason: "invalid", errors: %{field: [...]}}`.
- Another app's room, message or member is always `not_found`, never `forbidden` (like
  `delete_allowed_origin`).
- HTTP: 401 (credentials), 404, 422.
- Limits: text 1–4000 chars after trim; metadata a JSON object ≤ 4 KB; emoji one grapheme from a
  whitelist of ~30; 10 sends per 10s per socket (channel assigns), else `rate_limited`.

Security:

- Edit: author only. Delete: author, moderator, or the app over HTTP.
- Removing a member pushes `room.member.removed` to them and their room channel stops.
- App deletion cascades chat data; the origin cache refresh covers the origin check; token
  sockets get a best-effort `"disconnect"` broadcast on `chat_socket:<id>`, and their tokens fail
  on the next reconnect anyway.

Tests:

- DataCase per context: authorization matrix (wrong app, non-member, non-author, moderator),
  `client_ref` dedupe, `direct_key` uniqueness, `before`/`after` pagination, unread counts,
  deleted blanking and reply previews, reaction uniqueness and aggregation.
- ChannelCase: connect with no/valid/bad token; room join (membership, public self-join, origin,
  slug mismatch); each `handle_in` reply and its room/user broadcasts; gap fill; typing expiry
  (configurable timeout, `assert_push` with a timeout); presence with two sockets for one user;
  removed member kicked.
- ConnCase: token endpoint and room/member/send endpoints (401/404/422/201).
- LiveViewTest: Chat section, room page, moderation, superadmin-only controls; demo mounts.
- No JS test runner in v1 (the repo has none); SDK logic is checked through the demo.

## 7. Phases

Each phase ends with `mix precommit` and a commit.

1. Migrations and contexts for users, rooms, members, messages; token endpoint, socket auth, both
   channels with send/history/gap fill; server-side HTTP API; admin Chat section.
2. Presence, typing, read state and unread, `room.activity`.
3. Reactions, replies, edit/delete, moderation.
4. JS SDK, esbuild entry, demo page, README.
