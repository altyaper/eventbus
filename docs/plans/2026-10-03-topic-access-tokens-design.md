# Topic access tokens design

Lets an application decide who may listen to its topics. Its backend mints a short-lived token
that lists the topics a user may join, and eventbus checks it on `topic:` join. Today any socket
from an allowed origin can join any valid topic, and a socket with no `Origin` header (any
non-browser client) passes the origin check. So a topic's name is its only secret, and apps
have to keep payloads content-free.

The mechanism isn't specific to one app: the app picks the topic names and the grants, and
eventbus only checks that the grants stay inside the app's own namespace. changologs is the first
consumer (per-user notifications, board and log topics).

## Decisions

- **Grants in the token, decided by the app's backend.** The token carries topic patterns
  (`changologs.board.ab12.*`). Rejected: a fixed per-user convention such as
  `<slug>.user.<external_id>`, which covers notifications but not "members of board X". It also
  puts user ids into topic names, where emails and mixed-case ids fail the name format, and it
  takes over a namespace existing apps may already use for public topics.
- **The token goes in join params, not on the socket.** `socket.channel("topic:x", {token})`.
  The socket stays anonymous unless the client also uses chat. Rejected: grants on the socket
  token, because a socket's params are fixed at connect, so needing a new topic (opening another
  log) means reconnecting and rejoining every channel. Join params also keep large grant lists
  out of the WebSocket URL.
- **Minted over HTTP with app credentials**, like chat tokens (Ably token auth). Rejected: apps
  signing tokens themselves. `secret_hash` is a one-way hash, so eventbus would need a second
  secret per app that it can read back. This can be added later if minting latency matters.
- **Access per app, off by default.** A new `require_topic_tokens` setting on the app. Off, its
  topics behave exactly as today, plus tokens are honoured. On, joins need a token that grants
  the topic. Nothing that connects today breaks. Rejected: per-topic flags (no consumer needs
  mixed access yet, and it's a cache lookup per topic instead of per app).
- **Revocation is an API call, not just expiry.** The chat design rejected room capabilities in
  tokens because revocation only happened at expiry. That's addressed here with short TTLs (15
  min default), a revoke endpoint that kicks live channels, and a per-user `revoked_at` that
  refuses tokens minted earlier.
- **Chat is unchanged.** Its socket token and channels stay as they are. The two token kinds use
  different salts and can't be swapped.

## 1. Minting

`POST /api/tokens` (app Basic auth, `RequireAppCredentials`):

```json
{"user_id": "u_123", "grants": ["changologs.user.9f3c", "changologs.board.ab12.*"], "ttl": 900}
```

- `user_id`: the app's own id for the user (any string, 1–255 chars). Used for revocation and
  shown in telemetry. Never put into topic names.
- `grants`: 1–100 patterns. A pattern is an exact topic name, or a name ending in `.*` that
  matches every topic below it (`a.b.*` matches `a.b.c` and `a.b.c.d`, not `a.b`). Each must
  start with `<app slug>.` and, without the `.*`, pass `Topic.valid_name?/1`. `*` anywhere else
  is a 422.
- `ttl`: seconds, default 900, max 3600 (the chat token lifetime).
- Response `201 {token, expires_at}`. The token is a `Phoenix.Token` (salt `"topic grants"`) of
  `%{app: app_id, sub: user_id, grants: [...], iat: µs, exp: µs}`, both from
  `System.system_time(:microsecond)`. It's signed, not encrypted:
  the holder can read its own grants, so grant names mustn't carry secrets.

New module `Eventbus.TopicTokens` with `mint(app, attrs)` and `verify(token)`, alongside
`Eventbus.Chat.Tokens`. `verify` returns `{:ok, %{app_id, sub, grants, iat}}`, `{:error, :expired}`
or `{:error, :invalid}`.

## 2. Join

`TopicChannel.join("topic:" <> name, params, socket)`, in order:

1. Invalid name → `invalid topic name` (unchanged).
2. Origin not allowed for the slug → `origin not allowed` (unchanged).
3. `params["token"]` present: verify it. Expired → `token expired`, other failures →
   `invalid token`. The token's app must own the topic's slug and a grant must match, else
   `forbidden`. A token that was minted before the user's `revoked_at` → `token revoked`.
4. No token: allowed if the app doesn't require tokens, else `unauthorized`.

A token that is present but invalid is always refused, even on an open app, so client bugs
surface instead of silently falling back to anonymous.

The joined channel keeps `{app_id, sub}` in its assigns and subscribes to the PubSub topic
`topic_subscriber:<app_id>:<sub>` for kicks (§3).

`require_topic_tokens` lives in a `:persistent_term` cache keyed by slug, refreshed on toggle and
on app delete, so joins don't hit the DB (same pattern as `Eventbus.Origins`). The revocation
check is a DB lookup on an indexed `(application_id, user_id)` key, only when a token is present.

## 3. Revocation

`POST /api/tokens/revoke` (app Basic auth), `{"user_id": "u_123", "grants": ["changologs.board.ab12.*"]}`:

- With `grants`: channels of that user whose topic matches one of the patterns get pushed
  `revoked` and stop. Use this when a user loses access to one board.
- Without `grants`: every channel of that user is kicked, and `topic_revocations` is upserted
  with `revoked_at = now`, so tokens minted up to now (`iat <= revoked_at`) are refused on
  rejoin. `revoked_at` comes from the same clock as `iat`: `DateTime.utc_now/0` reads the OS
  clock, which drifts microseconds from the VM's `System.system_time/1`. Use this for logout, account removal, or "sign out other sessions".

Per-grant revocation doesn't invalidate the token. The app backend has to stop including that
grant in new tokens, and the old token stays usable for the revoked topic until it expires. That
gap is at most the TTL. Apps that can't accept it should use full revocation, which costs the
user a token refetch for their other topics.

Table `topic_revocations`: `application_id` (FK, on delete cascade), `user_id`, `revoked_at`, with
a unique index on `(application_id, user_id)`.

## 4. App settings

The app's **Settings** section (superadmin) gets a "Require tokens to listen" toggle, with a note
that anonymous listeners will be refused once it's on. The app's topic page in the admin UI is
unaffected: it subscribes to PubSub server-side (`TopicShowLive`), not through `TopicChannel`.

## 5. Clients

phoenix.js accepts a function for channel params and calls it on every rejoin, so a client can
supply a fresh token after reconnecting:

```js
const channel = socket.channel(`topic:${name}`, () => ({token: currentToken}))
channel.join().receive("error", ({reason}) => {
  if (reason === "token expired" || reason === "token revoked") refreshTokenThenRejoin()
})
channel.on("revoked", () => channel.leave())
```

- No bundled helper: browser clients use plain `phoenix` (changologs) or the separate
  `@altyaper/eventbus-react` package, whose `useTopic` needs a `getToken` option (follow-up in
  that repo).
- README and `/docs`: a "Private topics" section covering the mint request, a backend example,
  join params and revocation.

## 6. Errors and testing

| Case | Result |
|---|---|
| Grant outside the app's slug, bad pattern, >100 grants, ttl out of range | 422 with field errors |
| Token for app A joining app B's topic | `forbidden` |
| Topic not covered by any grant | `forbidden` |
| Expired / tampered / chat token in join params | `token expired` / `invalid token` |
| Token minted before full revocation | `token revoked` |
| Open app, no token | joins (today's behaviour) |
| Token-required app, no token | `unauthorized` |
| App deleted | tokens fail (app lookup), revocations cascade |

- Tests: pattern validation and matching (exact, `.*` depth, no partial-segment match),
  mint/verify round trip, expiry; ChannelCase joins for every row above, with origin checks
  still applied; revoke kicks only matching channels of only that user; full revoke refuses old
  tokens and accepts newer ones; the setting's cache refreshes on toggle and app delete; Settings
  toggle LiveView.
- Verified end to end with two Node clients against a dev server: an open app, a token-required
  app, a token refreshed mid-session, a per-grant kick.

## changologs (consumer, separate change)

1. Rails: `GET /api/eventbus_token?topics[]=…`. It checks the user can see each requested
   board or log, then mints with `EVENTBUS_CLIENT_ID`/`SECRET` and always includes
   `changologs.user.<hex hash_id>`.
2. Web: `utils/eventbus.ts` passes `() => ({token})` as join params and refreshes the token.
3. Rails calls revoke on share removal (per grant) and on logout or session revocation (full).
4. Turn on "Require tokens to listen" for `changologs`. Per-user events (notifications, friend
   requests, share changes) can then be published.
