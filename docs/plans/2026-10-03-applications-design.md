# Applications design

Adds applications as a first-class layer over topics. Each application owns the topics named
`<slug>.*` and has its own `client_id` and secret, which replace the shared instance API key for
publishing. Supersedes the API-key publishing parts of
[2026-10-01-eventbus-design.md](2026-10-01-eventbus-design.md) and
[2026-10-03-auth-setup-design.md](2026-10-03-auth-setup-design.md).

## Decisions

- **Topic ↔ app link: name prefix.** Application `changologs` owns every topic named
  `changologs.*`, also stored as a foreign key. Credentials can only publish inside their own
  prefix. Rejected: free topic names with an explicit link, which allows collisions across apps
  and needs the app in every publish URL.
- **Instance API key: setup only.** It no longer authorizes publishing; it's only the proof of
  ownership at `/setup`. Rejected: keeping it as a master key, which would be a second
  all-powerful credential.
- **Auth: HTTP Basic** (`client_id:secret`). Rejected: OAuth2 client credentials (token refresh
  logic in every client, overkill here) and custom headers (no built-in client support).
- **Existing topics: start clean.** The migration deletes all topics.
- **WebSocket publish: removed.** Publishing is HTTP-only; the socket is for listening.

## 1. Data and credentials

`applications`: `slug` (unique, `[a-z0-9_-]`, no dots, immutable), `client_id` (unique, public,
`ebc_…`), `secret_hash` (SHA-256 of a 32-byte random secret), timestamps. The secret is shown once
at creation or regeneration and never stored. SHA-256 rather than bcrypt because the secret is
high-entropy and bcrypt would add ~100 ms to every publish.

`topics`: new required `application_id` (on delete cascade). Names must be `<slug>.<rest>` of their
application.

Topic rows are created by authenticated HTTP publishes (auto-create inside the app) and by the UI.
Channel joins no longer create rows; listening works for any valid name without one.

Publishing: `POST /api/topics/:name/events` with `Authorization: Basic base64(client_id:secret)`.
`401` for missing, malformed or wrong credentials (constant-time compare, no hint whether the
client exists); `403` for a topic outside the app; `422` for an invalid name; `202` with the event
otherwise.

## 2. UI

- `/` becomes the Applications page: apps sorted by slug, topics nested under each. Each app
  header has Credentials and Delete app (inline confirmation; deletes its topics).
- "New application" card: slug field; on create, a one-time panel shows `client_id` and secret
  with copy buttons.
- "New topic" card: app dropdown plus name, previewing the full name; disabled with no apps.
- Credentials panel: `client_id` with copy, Regenerate secret (inline confirmation; the old secret
  stops working immediately), then the one-time secret panel.
- Quick start: `curl -u <client_id>:<secret>` against the browser's current origin.
- Creating/deleting apps, viewing credentials and regenerating secrets are superadmin-only.
- The topic page's test-publish form is unchanged (logged-in users publish directly).
- The API key leaves the user menu.

## 3. Errors, migration, testing

- Malformed `Authorization` → `401`, same body as wrong credentials.
- Slugs can't be renamed (would silently change every topic name). Create a new app instead.
- Deploying breaks existing publishers until they switch to app credentials.
- Tests: application validation and credentials lifecycle; topic/app name matching; publish API
  status codes; channel join without row creation and no `"publish"`; LiveView create app, one-time
  secret, create topic, regenerate, delete, and superadmin-only controls.
