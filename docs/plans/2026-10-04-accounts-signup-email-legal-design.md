# Accounts: signup, email confirmation, password recovery, legal pages

Turns eventbus from a single-operator tool into a multi-tenant service: anyone can sign up, each
user owns and sees only their own apps, and email drives confirmation and password recovery. Adds
public Privacy Policy and Terms pages. This supersedes the username-only identity and the "no
mailer" reasoning in [2026-10-03-auth-setup-design.md](2026-10-03-auth-setup-design.md); its
session, scope and `on_mount` design stays.

## Decisions

- **Tenancy: isolated per user.** Apps get an `owner_id`; every app, topic and chat page is scoped
  to the owner. Other users' slugs 404.
- **Identity: email only.** `username` is dropped. Login, header and `/setup` use email.
- **Confirmation: soft.** Users are logged in right after signup and confirm later. Until
  confirmed they get one app (an auto-created sandbox) and at most 5 topics. Confirming lifts both
  limits immediately.
- **Sandbox app at signup.** Every new user gets `sandbox-<6 random base32 chars>` so they can try
  publishing straight away.
- **Superadmin = operator.** `/setup` still creates the first account (now with email) and blocks
  signup until done. The superadmin owns the pre-existing apps and keeps operator features (API
  key reveal) but does not see other users' apps.
- **Email: Resend** via `Swoosh.Adapters.Resend`.
- **Legal: static HEEx pages + required consent** checkbox at signup, stored as
  `accepted_terms_at`.
- **Approach: extend the hand-rolled `Accounts` context.** `phx.gen.auth` (magic-link-first in
  1.8) would collide with the existing `User`, `UserToken`, `UserAuth`, `Scope` and setup flow;
  a library like Pow fits poorly with 1.8 scopes. Both rejected.

## 1. Data model and migration

| table | change |
|---|---|
| `users` | add `email` (`citext`, unique, required, max 160, basic format), `confirmed_at` (nullable), `accepted_terms_at` (required at signup); drop `username`; `role` is `"superadmin"` or `"member"` (signups are `member`) |
| `users_tokens` | add `sent_to`; new contexts `"confirm"` (valid 7 days) and `"reset_password"` (valid 1 day) |
| `applications` | add `owner_id` → `users` (`on_delete: :delete_all`, required, indexed); slugs stay globally unique because topic names are global |

Email tokens: 32 random bytes, url-safe base64 in the link, only the SHA-256 hash stored. A token
is rejected if `sent_to` no longer matches the user's email.

**Existing installs.** The data migration reads `EVENTBUS_ADMIN_EMAIL` and fails with a clear
message if it's unset while users exist. It sets the superadmin's email, marks `confirmed_at` and
`accepted_terms_at` as now, and assigns every existing app to them. Fresh installs need nothing.

**Sandbox.** Created in the same transaction as the user; retries on slug conflict. Its secret is
revealed once on first dashboard visit, like any app.

**Limits, enforced in contexts:**

- `Applications.create_app(scope, attrs)` → `{:error, :unconfirmed}` if the user isn't confirmed.
- `Topics.create_topic/2` → `{:error, :topic_limit}` when the app's owner is unconfirmed and
  already owns 5 topics. Both the UI form and API auto-create go through this function.

## 2. Routes and web flows

```
public               /privacy, /terms              LegalController (static HEEx)
logged-out only      /signup                       SignupLive
                     /login                        LoginLive (email + password)
                     /reset-password               ResetPasswordRequestLive
                     /reset-password/:token        ResetPasswordLive
any state            /confirm/:token               ConfirmController :show
logged in            POST /confirm/resend          ConfirmController :resend
```

- **Signup:** email, password + confirmation, required terms checkbox linking both pages. Live
  validation without bcrypt. One transaction creates user + sandbox, sends the confirmation email,
  then logs in via `phx-trigger-action` → `SessionController` and lands on `/apps`. Guarded by
  `:require_setup`.
- **Confirm:** valid link sets `confirmed_at`, deletes the user's `"confirm"` tokens, redirects
  with a flash (to `/apps` or `/login`). Invalid/expired shows a neutral message. Unconfirmed
  users see a persistent banner in `Layouts.app` with a Resend button; "Create app" is disabled
  and the topic form shows "3/5 topics — confirm your email to remove the limit".
- **Password recovery:** the request form always answers "If that email exists, we've sent a
  link". The reset form sets a new password, deletes **all** the user's tokens (sessions
  included), disconnects live sockets, and sets `confirmed_at` if empty. No auto-login; the user
  goes to `/login`.
- **Scoping:** `/apps/:slug/*` LiveViews load via `Applications.get_owned_app!(scope, slug)`
  (404 for others). `AppsLive` lists own apps only. Any user can create/delete their own apps
  (subject to confirmation); the superadmin-only gate in `AppsLive` is removed.

Out of scope: change email/password settings page, account deletion, OAuth.

## 3. Email, errors and security

- `Eventbus.Accounts.UserNotifier` sends plain-text confirmation and reset emails with links
  built by `url(~p"/confirm/#{token}")`, so `PHX_HOST` must be right in prod.
- Prod: `Swoosh.Adapters.Resend` with `Swoosh.ApiClient.Req`, from `RESEND_API_KEY` and
  `MAIL_FROM` in `runtime.exs`. If `RESEND_API_KEY` is unset, log a warning at boot and fall back
  to `Swoosh.Adapters.Logger` so self-hosters still run. Dev keeps `/dev/mailbox`; tests use
  `Swoosh.Adapters.Test`.
- Delivery is synchronous; a failure is logged and never rolls back signup or reset.
- **Cooldown:** no new `"confirm"`/`"reset_password"` token if one of the same context was issued
  for the user within 60 seconds (silent for reset, "please wait a minute" for resend).
- Signup with an existing email shows the uniqueness error; this reveals registration, an
  accepted trade-off.
- Unchanged: password 12–72 chars, `Bcrypt.no_user_verify/0` for timing, "Invalid email or
  password", API-key-guarded `/setup` for the first account.
- Publish API maps `:topic_limit` to `403`
  `{"error": "topic_limit", "message": "Confirm your email to create more than 5 topics"}`.
- **Legal pages:** "Last updated: 2026-10-04". Privacy draft covers what is stored (email, hashed
  password, app/topic names, chat messages), that event payloads are not persisted, session
  cookie only, Resend as email processor, and deletion requests. Terms draft covers acceptable
  use, no SLA, termination and liability. Both are drafts to review before launch.

## 4. Testing

- **Accounts:** signup creates member + sandbox atomically, terms required, email unique
  case-insensitively; confirm token valid/single-use/expired/`sent_to` mismatch/tampered;
  cooldown; reset deletes every token and sets `confirmed_at`.
- **Limits:** unconfirmed → `:unconfirmed` on `create_app`, `:topic_limit` on the 6th topic;
  both pass after confirming.
- **Ownership:** `get_owned_app!/2` raises for another user's slug; app list is own-only.
- **LiveViews/controllers (by element ID):** signup validation and success with
  `assert_email_sent`; confirm logged in/out and invalid; resend cooldown; reset request with
  unknown email sends nothing; full reset logs out old sessions; banner and disabled "Create app"
  only while unconfirmed; other user's `/apps/:slug` 404s; publish API 403 on 6th topic;
  `/privacy` and `/terms` render logged out and are linked from the footer.
- **Helpers:** `register_and_log_in_user` creates a confirmed member by default, with
  `unconfirmed: true`; app/topic fixtures take an `owner`.
- **Migration:** with an existing user and `EVENTBUS_ADMIN_EMAIL`, the superadmin gets the email,
  is confirmed, and owns the existing apps.
