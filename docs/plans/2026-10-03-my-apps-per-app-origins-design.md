# My Apps and per-app origins design

Adds a **My Apps** section with a page per application, and moves allowed websocket origins from
instance-wide Settings onto each application. Supersedes the Settings/origins parts of
[2026-10-03-applications-design.md](2026-10-03-applications-design.md).

## Decisions

- **App sections: Topics · Credentials · Origins · Settings.** Settings holds the danger zone
  (delete app). Rejected: an Overview landing (nothing to put there yet) and merging credentials
  with origins into one "Access" page.
- **My Apps is a plain top-menu link** to `/apps`. Rejected: a dropdown app switcher (extra UI
  for a handful of apps).
- **Existing global origins are copied onto every app** so nothing that connects today breaks.
  Rejected: dropping them.
- **Global Settings is removed** (page and user-menu link); it has nothing editable left. The
  environment origins are shown read-only on each app's Origins page.
- **Two-step enforcement.** Phoenix checks the origin at socket connect, before it knows which
  topics will be joined, so per-app origins are enforced at channel join. Rejected: one socket
  per app (`/socket?app=…`), which changes every client.

## 1. Routes and navigation

| Route | Page | Access |
|---|---|---|
| `/` | redirect to `/apps` | logged in |
| `/apps` | My Apps: app cards (slug, topic count, client ID) + New application (one-time secret) | logged in; create is superadmin |
| `/apps/:slug` | redirect to `/apps/:slug/topics` | |
| `/apps/:slug/topics` | topic list + New topic (prefix `slug.` fixed) | logged in |
| `/apps/:slug/topics/:name` | topic page (live events + test publish) | logged in |
| `/apps/:slug/credentials` | client ID, regenerate secret, curl quick start | superadmin |
| `/apps/:slug/origins` | add/remove this app's origins; env origins read-only | superadmin |
| `/apps/:slug/settings` | delete app → back to `/apps` | superadmin |

`/settings` and `/topics/:name` are removed.

- Top bar: "Topics" becomes **My Apps**, active on `/apps/*`. Settings leaves the user menu.
- Inside an app: header with breadcrumb (`My Apps / <slug>`) and a section menu, a left sidebar
  on desktop and horizontal tabs on mobile. Non-superadmins see only Topics.
- One `AppLive` with `live_action`s `:topics | :credentials | :origins | :settings` and `patch`
  links, so the app loads once. The topic page stays its own LiveView inside the same shared
  `app_shell` function component.
- `TopicsLive.Index` is split: app creation moves to `AppsLive`; topics, credentials and delete
  move into the sections.

## 2. Data and enforcement

- `allowed_origins` gains a required `application_id` (FK, on delete cascade). The unique index
  moves from `origin` to `(application_id, origin)`.
- `Origins` becomes per-app: `list_allowed_origins(app)`, `create_allowed_origin(app, attrs)`,
  `delete_allowed_origin(app, id)`. `Pattern` canonicalisation is unchanged.
- Migration: add the column, copy each existing origin onto every app, delete the app-less rows,
  swap the index. With no apps, the old origins are dropped.
- Cache in `:persistent_term`: `%{env: [...], by_app: %{slug => [...]}}`, refreshed on origin
  add/delete and on app delete. Joins look up by the topic's slug prefix, never the DB.

Enforcement:

1. **Connect** (endpoint `check_origin`): env origins ∪ every app's origins.
2. **Join** (`TopicChannel.join/3`): for `topic:<slug>.*`, the origin must be an env origin or on
   that app's list, else `{:error, %{reason: "origin not allowed"}}`.

The channel gets the origin through the endpoint: an overridden `call/2` deletes any
client-supplied `x-eventbus-origin` header and copies `Origin` into it; `UserSocket` uses
`connect_info: [:x_headers]` and stores the parsed origin in `socket.assigns.origin`. Browsers
can't forge `Origin` and the header is always overwritten.

Edge cases:

- No `Origin` header (server-side clients): allowed, matching Phoenix.
- Env origins (`PHX_HOST` / `PHX_EXTRA_ORIGINS`) may join any app's topics: they're the
  instance itself and can't be removed from the UI.
- `check_origin: false` (dev): the join check is skipped too.
- `/live` stays under the connect gate only; an app origin reaching it still needs a session and
  CSRF token. A separate env-only check would override `check_origin: false` in dev.

## 3. Errors and testing

- Unknown slug → flash and redirect to `/apps`. Non-superadmin on a restricted section → redirect
  to the app's Topics. Topic outside the app's prefix → redirect to the app's Topics. Duplicate
  origin → inline "is already allowed".
- Tests: per-app origin CRUD, same origin on two apps, cache cleared on app delete; channel join
  allowed for app/env/no origin, rejected for another app's origin, skipped when checks are off;
  endpoint overwrites a spoofed `x-eventbus-origin`; LiveViews for `/apps`, each section, patch
  navigation, origins add/remove, regenerate, delete, non-superadmin visibility, `/` redirect,
  `/settings` gone; topic page tests on the new route.
- README: note that browser listeners need their site under the app's Origins.
