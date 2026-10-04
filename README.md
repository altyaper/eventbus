# Eventbus

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Running with Docker (e.g. on a Raspberry Pi)

```
cp docker.env.example .env
# edit .env: set SECRET_KEY_BASE (mix phx.gen.secret), PHX_HOST, POSTGRES_PASSWORD
docker compose up -d --build
```

**First run:** open the app and you land on `/setup`, which creates the superadmin account.
It asks for the server's API key as proof you own the install. Unless you set
`EVENTBUS_API_KEY` yourself, a key is generated on first boot, stored in the database and
printed in the logs until setup is done (`docker compose logs app`). That's its only use.

**Publishing:** create an application under **My Apps** (e.g. `changologs`). It owns every topic
named `changologs.*` and gets a client ID and secret (the secret is shown once). Publish with
HTTP Basic auth:

```
curl -u "$CLIENT_ID:$CLIENT_SECRET" -X POST http://raspberrypi.local:4000/api/topics/changologs.logs/events \
  -H "Content-Type: application/json" -d '{"hello": "world"}'
```

**Listening from a browser:** join `topic:<name>` on the `/socket` WebSocket. Pages on other
sites need their origin added on the app's **Origins** page, and may then only listen to that
app's topics. `PHX_HOST` and `PHX_EXTRA_ORIGINS` are always allowed, for every app.

**Chat:** each application also gets chat rooms for its own users (messages, history, replies,
edits, reactions, typing, presence, unread counts). eventbus never logs those users in: the app's
backend vouches for them by minting a short-lived token with its credentials.

```
# Your backend, for its logged-in user (the response is what the SDK's getToken returns)
curl -u "$CLIENT_ID:$CLIENT_SECRET" -X POST http://raspberrypi.local:4000/api/chat/tokens \
  -H "Content-Type: application/json" -d '{"user_id": "ann", "display_name": "Ann"}'

# Rooms and members are managed server-side too
curl -u "$CLIENT_ID:$CLIENT_SECRET" -X POST http://raspberrypi.local:4000/api/chat/rooms \
  -H "Content-Type: application/json" -d '{"type": "group", "name": "engineering", "members": ["ann", "bo"]}'
```

Other endpoints (same Basic auth): `POST /api/chat/rooms/:id/members` (`user_id`, `role`),
`DELETE /api/chat/rooms/:id/members/:user_id`, `POST /api/chat/rooms/:id/messages` (send as a
user, e.g. a bot) and `DELETE /api/chat/rooms/:id/messages/:message_id` (moderation). Direct
rooms are `{"type": "direct", "members": ["ann", "bo"]}`.

In the browser, load the SDK from eventbus and build your own UI on its events:

```html
<script src="http://raspberrypi.local:4000/assets/js/chat.js"></script>
<script>
  const chat = new EventbusChat.Chat({
    url: "ws://raspberrypi.local:4000/socket",
    getToken: () => fetch("/my-backend/chat-token").then(r => r.json()),
  })
  await chat.connect()
  chat.rooms.on("change", rooms => renderSidebar(rooms))   // unread counts, latest message
  const room = await chat.room(roomId).attach()
  room.messages.on("change", messages => renderMessages(messages))
  room.typing.on("change", () => renderTyping(room.typing.label()))
  room.presence.on("change", online => renderOnline(online))
  room.send("hi", {replyTo: messageId})       // shows at once, reconciled with the server
  room.typing.keystroke()                      // on input; throttled for you
  room.markRead()                              // when the newest message is in view
</script>
```

The site's origin needs to be on the app's **Origins** page, as for topics. The app's **Chat**
section lists rooms and moderates them, and **Try it in the demo** chats as any user through the
same SDK (open two windows as different users). The channel contract (`chat:<slug>:<room id>`,
`chat_user:<slug>:<user id>` and their events) is in `docs/plans/2026-10-03-chat-design.md`.

Build this directly on the target machine so Docker picks the right CPU architecture
automatically (no cross-compilation needed). The app runs plain HTTP on the LAN
(`force_ssl` is disabled) and applies Ecto migrations automatically on startup.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
