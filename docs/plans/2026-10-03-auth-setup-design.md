# Auth and initial setup design

Adds user accounts to eventbus. A fresh install shows a one-time setup screen that creates a
superadmin; after that, the web UI requires login. This supersedes the "no per-user accounts" line
in [2026-10-01-eventbus-design.md](2026-10-01-eventbus-design.md) for the web UI only.

## Decisions

- **Scope: web UI only.** `/` and `/topics/:name` require login. `/api` keeps the shared API key and
  `/socket` stays open, so changologs, scripts and external browser clients keep working.
- **Hand-rolled, gen.auth-style.** A small `Accounts` context with DB-backed session tokens and
  `on_mount` hooks. `phx.gen.auth` was rejected because Phoenix 1.8's generator is built around
  email, magic links and a mailer, none of which apply to a username-based personal tool.
- **Setup guard: the API key.** The setup form asks for `EVENTBUS_API_KEY`, which proves ownership
  of the deployment. Every install generates its own key and prints it in the logs until setup is
  done.
- **Key storage: DB, env overrides.** An explicit `EVENTBUS_API_KEY` env var still wins, so existing
  installs keep their key. Otherwise the key is generated once and persisted in Postgres.

## 1. Data and the API key

Tables:

| table | columns |
|---|---|
| `users` | `username` (unique, lowercase, 3–32 chars of `a-z0-9._-`), `hashed_password` (bcrypt), `role` (`"superadmin"`; `"member"` reserved for later), timestamps |
| `users_tokens` | `user_id`, `token` (32 random bytes), `context` (`"session"`), `inserted_at` |
| `settings` | `key` (unique), `value` — currently only `api_key` |

Session tokens expire after 60 days. Logging out deletes the token row.

`Eventbus.Settings.api_key/0` resolves the key in order:

1. `EVENTBUS_API_KEY` env var, if set.
2. The `api_key` row in `settings`.
3. Otherwise generate one (`:crypto.strong_rand_bytes(32)`, url-safe base64), insert race-safely,
   use it.

A boot-time task resolves the key after migrations and caches it in `:persistent_term` so the
publish plug never hits the DB. While no users exist it logs the key and the `/setup` URL on every
boot. The `dev-secret` defaults in `runtime.exs` and `docker-compose.yml` are removed.

## 2. Web flow and protection

```
/setup            SetupLive                  only while no users exist
/login            LoginLive                  form posts to the controller below
POST /login       SessionController.create   sets the session cookie
DELETE /logout    SessionController.delete
/  /topics/:name  existing LiveViews, login required
```

- `fetch_current_scope` plug in `:browser` loads the user from the session token into
  `@current_scope` (`%Eventbus.Accounts.Scope{user: user}`), per Phoenix 1.8 conventions.
- `on_mount` hooks: `:require_setup` (no users → `/setup`), `:require_authenticated` (→ `/login`),
  `:redirect_if_authenticated` (keeps logged-in users off `/login`).
- Setup validates username, password (min 12 chars) + confirmation, and the API key
  (`Plug.Crypto.secure_compare`). Creating the superadmin re-checks "no users" inside a
  transaction, so setup can't be re-run or raced. On success it logs in via `phx-trigger-action`.
- Login failures always say "Invalid username or password"; `Bcrypt.no_user_verify/0` keeps the
  timing equal for unknown usernames.
- Header shows username, role badge and Log out when logged in. The superadmin can reveal and copy
  the API key from the header.

Out of scope: inviting more users. The `role` column and hooks are the foundation for it.

## 3. Errors and security

- The app fails to start if the API key can't be resolved (DB down), rather than running keyless.
- A deleted/expired session token means logged out. Logout broadcasts `"disconnect"` to the user's
  live socket id.
- Session renewed on login (`configure_session(renew: true)`); cookie `same_site: "Lax"`. No
  `secure` flag yet, since the LAN deployment is plain HTTP.
- No login rate limiting for now.

## 4. Testing

- `Accounts`: superadmin creation only with zero users, validations, credential check, session
  token lifecycle and expiry.
- `Settings`: env override, generate-and-persist, stable across calls.
- `RequireApiKey` and the publish controller against the resolved key.
- LiveViews: redirect to `/setup` with no users; setup wrong key / success; `/setup` locked after;
  logged-out redirects to `/login`; bad and good login; logout.
- `register_and_log_in_user` ConnCase helper keeps the existing topic tests passing.
