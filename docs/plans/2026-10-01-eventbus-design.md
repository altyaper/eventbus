# eventbus design

A personal, general-purpose real-time event bus. Any app (changologs, scripts, curl) publishes
JSON events to a named topic over HTTP; any client (JS in a browser, or this app's own admin UI)
subscribes over a WebSocket to watch that topic's events arrive live. Built with Phoenix because
Channels + PubSub are exactly this problem.

## 1. Architecture

Standalone Phoenix app at `~/Development/ppersonal/eventbus`, sibling to `changologs`, not tied
to it.

- **Topics** — persisted rows in Postgres (name only). A `Topics` context owns CRUD and
  `get_or_create_by_name/1`.
- **Phoenix Channels** (`EventbusWeb.TopicChannel`) — the real-time transport. A client joins
  `"topic:<name>"` and receives every event broadcast to that topic via `Phoenix.PubSub`.
- **HTTP publish endpoint** — `POST /api/topics/:name/events`, gated by a shared API key,
  broadcasts straight to the channel topic. No DB write of the event itself — live-only,
  fire-and-forget.
- **WS publish** — the channel also handles an incoming `"publish"` event, so a socket already
  joined to a topic can push events into it, not just receive them.
- **LiveView admin UI** — list/create topics, click one to open a live-updating feed — the
  "start listening" experience, with an explicit Start/Stop toggle and a manual test-publish
  form.

No event storage, no replay, no per-user accounts — single shared API key, in-memory channel
state only.

## 2. Data model

`topics` table:

| column | type | notes |
|---|---|---|
| `id` | bigserial | |
| `name` | string, unique, not null | identifier used in channel joins and the publish URL, e.g. `"changologs.logs"` |
| `inserted_at` / `updated_at` | timestamps | |

That's the whole schema. No `events` table (live-only), no `users` table (shared API key), no
subscriptions table (Channels track connections in-memory).

**Topic name rules:** lowercase alphanumeric plus `.`, `-`, `_`, validated by
`Eventbus.Topics.valid_name?/1` and used both server-side and in the LiveView create form.

**Auto-create on publish:** `POST /api/topics/:name/events` or a channel `join` against an
unknown name creates the topic row rather than failing — lowest friction for new publishers. The
LiveView UI is for browsing/watching, not a hard gate on what topics can exist. Race-safe via a
unique index on `topics.name` with `on_conflict: :nothing`, re-fetching on conflict.

**Event shape:** free-form JSON payload. eventbus wraps it server-side as
`%{"payload" => <submitted body>, "published_at" => DateTime.utc_now()}` and broadcasts that
envelope as-is — no fixed `{type, payload}` schema.

## 3. HTTP API (publish)

```
POST /api/topics/:name/events
Headers: Authorization: Bearer <EVENTBUS_API_KEY>
Body:    any JSON object
```

Flow: check API key (401 if wrong/missing) → validate topic name (422 if invalid) →
`Topics.get_or_create_by_name(name)` → `Eventbus.Events.publish(name, body)` (builds the
envelope, broadcasts via `Phoenix.PubSub.broadcast(Eventbus.PubSub, "topic:#{name}", {:event,
event})`) → respond `202` with the full published event (topic + payload + published_at).

No topic-management REST endpoints — the LiveView UI drives topic CRUD directly through the
`Topics` context. No rate limiting or body-size limits for v1 — personal tool behind one shared
key.

## 4. WebSocket (Phoenix Channels)

- **Socket:** `EventbusWeb.UserSocket` at `/socket`, no per-connection auth on `connect/3` — the
  API key gates publishing, not listening.
- **Channel:** `EventbusWeb.TopicChannel`, topic pattern `"topic:*"`.
  - `join("topic:" <> name, _params, socket)` validates the name, calls
    `Topics.get_or_create_by_name/1`, returns `{:ok, socket}`.
  - Any broadcast on `"topic:#{name}"` (from HTTP publish or another socket's WS publish) is
    pushed to the client as a `"event"` message.
  - `handle_in("publish", payload, socket)` calls the same `Eventbus.Events.publish/2` used by
    the HTTP controller, and replies `{:ok, event}` to the sender — HTTP and WS publish share one
    code path, so there's a single source of truth for the envelope shape.

JS usage (official `phoenix` npm package, no custom wrapper):

```js
import {Socket} from "phoenix"
let socket = new Socket("/socket")
socket.connect()
let channel = socket.channel("topic:changologs.logs", {})
channel.join()
channel.on("event", payload => console.log(payload))
channel.push("publish", {hello: "world"})
```

## 5. LiveView admin UI

- **`EventbusWeb.TopicsLive.Index`** (`/`) — lists topics (`Topics.list_topics/0`, newest
  first), a form to create one directly, links to each topic's show page.
- **`EventbusWeb.TopicShowLive`** (`/topics/:name`) — Start/Stop Listening toggle that
  subscribes/unsubscribes `Phoenix.PubSub.subscribe(Eventbus.PubSub, "topic:#{name}")`;
  `handle_info({:event, event}, socket)` prepends to a capped in-memory list (last ~100) and
  re-renders each event as timestamp + pretty-printed JSON; a manual "Publish test event" form
  on the same page reuses `Eventbus.Events.publish/2` for debugging without curl.

## 6. Error handling

- Bad/missing API key → `401`.
- Invalid topic name → `422`, one shared validation (`Eventbus.Topics.valid_name?/1`) used by
  both the HTTP controller and the LiveView create form.
- Malformed JSON body → handled by `Plug.Parsers` (`400`), no custom handling needed.
- WS publish payload → already valid JSON by the time it reaches `handle_in/3`; nothing further
  to validate given the free-form event shape.
- Broadcast with zero listeners → normal, not an error.
- Concurrent topic creation race → unique index + `on_conflict: :nothing`, re-fetch on conflict.

Out of scope: error tracking/Sentry, retries, dead-letter handling for undelivered events —
fire-and-forget by design.

## 7. Testing

- `Eventbus.TopicsTest` — name validation, uniqueness, `get_or_create_by_name/1` idempotency
  and race-safety.
- `Eventbus.EventsTest` — `publish/2` builds the right envelope and broadcasts on the expected
  PubSub topic.
- `EventbusWeb.TopicChannelTest` (`Phoenix.ChannelTest`) — join auto-creates unknown topics,
  broadcasts arrive as `"event"` pushes, `handle_in("publish", ...)` broadcasts and echoes.
- `EventbusWeb.TopicControllerTest` (`ConnCase`) — 401/202/422 paths, auto-create on first
  publish, full event echoed in the response.
- `Phoenix.LiveViewTest` — `TopicsLive.Index` lists/creates; `TopicShowLive` renders a pushed
  PubSub event live, the Start/Stop toggle actually stops rendering new events, and the
  test-publish form round-trips through `Events.publish/2`.

No external integration test against a real JS client (manual verification via a tiny HTML page
or the LiveView UI is enough) and no load/perf testing — out of scope at this scale.

## Decisions ruled out (YAGNI)

- Event persistence/replay — live-only, per-topic history not needed yet.
- Per-user accounts / multi-tenant auth — single shared API key is enough for a personal tool.
- Custom JS client wrapper — official `phoenix` npm package is sufficient.
- Topic-management REST API — LiveView UI is the only topic-CRUD surface.
- Rate limiting, retries, dead-letter queues — not needed at personal-tool scale.
