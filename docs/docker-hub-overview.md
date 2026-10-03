# eventbus

A tiny, self-hosted **real-time event bus** built with Elixir and Phoenix. Publish JSON events to a
named topic over HTTP or WebSocket, and every subscriber on that topic gets them instantly. A
built-in web UI lets you browse topics and watch events stream in live.

Designed to run on small hardware: a Raspberry Pi on your LAN is the reference target.

- **Publish over HTTP**: `POST /api/topics/:name/events` with a bearer API key
- **Subscribe over WebSocket**: standard Phoenix Channels on `/socket`
- **Live web UI**: list topics, open one, and watch events arrive in real time
- **Topics are created on first use**: no setup step before publishing
- **Migrations run automatically** on container start

> Events are **live-only**. They are broadcast to whoever is connected at that moment and are not
> stored or replayed. Postgres holds only the list of topic names.

---

## Quick start (Docker Compose)

eventbus needs PostgreSQL. This `docker-compose.yml` runs both:

```yaml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: eventbus
      POSTGRES_PASSWORD: change-me
      POSTGRES_DB: eventbus_prod
    volumes:
      - db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U eventbus"]
      interval: 5s
      timeout: 5s
      retries: 10

  app:
    image: jorgechavzns/eventbus:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: ecto://eventbus:change-me@db/eventbus_prod
      SECRET_KEY_BASE: <64+ random chars>
      PHX_HOST: raspberrypi.local
    ports:
      - "4000:4000"

volumes:
  db_data:
```

```sh
docker compose up -d
```

Then open **http://raspberrypi.local:4000** (or whatever host you set in `PHX_HOST`).

Generate a `SECRET_KEY_BASE` with any of:

```sh
openssl rand -base64 48
mix phx.gen.secret        # if you have Elixir installed
```

## Quick start (`docker run`)

If you already have a Postgres server:

```sh
docker run -d --name eventbus \
  -p 4000:4000 \
  -e DATABASE_URL=ecto://USER:PASS@HOST/eventbus_prod \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=192.168.1.50 \
  jorgechavzns/eventbus:latest
```

The database must already exist. eventbus creates its own tables on startup.

**First run:** open the app and you land on `/setup`, which creates the superadmin account. It
asks for the API key, which is generated on first boot and printed in the container logs
(`docker logs eventbus`) until setup is done. Afterwards the superadmin can copy it from the user
menu.

---

## Configuration

| Variable           | Required | Default       | Description                                                                 |
| ------------------ | -------- | ------------- | --------------------------------------------------------------------------- |
| `DATABASE_URL`     | yes      | —             | Postgres URL, e.g. `ecto://user:pass@db/eventbus_prod`                      |
| `SECRET_KEY_BASE`  | yes      | —             | Signs cookies and sessions. At least 64 random characters.                  |
| `EVENTBUS_API_KEY` | no       | generated     | Bearer token for HTTP publishing and `/setup`. Generated and stored on first boot if unset. |
| `PHX_HOST`         | no       | `example.com` | Hostname or IP clients use to reach the app. Used for URLs and origin checks. |
| `PORT`             | no       | `4000`        | HTTP port inside the container                                              |
| `POOL_SIZE`        | no       | `10`          | Database connection pool size                                               |
| `ECTO_IPV6`        | no       | unset         | Set to `true` to connect to Postgres over IPv6                              |

---

## Usage

### Publish an event (HTTP)

```sh
curl -i http://raspberrypi.local:4000/api/topics/sensors.kitchen/events \
  -H "Authorization: Bearer $EVENTBUS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"temperature": 21.5}'
```

Response: `202 Accepted` with the event envelope that was broadcast:

```json
{
  "topic": "sensors.kitchen",
  "payload": { "temperature": 21.5 },
  "published_at": "2026-10-02T14:03:11.402918Z"
}
```

| Status | Meaning                                  |
| ------ | ---------------------------------------- |
| `202`  | Event accepted and broadcast             |
| `401`  | Missing or wrong `Authorization` header  |
| `422`  | Invalid topic name                       |

**Topic names** are lowercase letters, digits, `.`, `-` and `_`, and must start and end with a
letter or digit. Examples: `orders`, `sensors.kitchen`, `build-status`.

### Subscribe (WebSocket)

eventbus uses the standard [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html) protocol.
Connect to `/socket` and join `topic:<name>`. Each event arrives as an `"event"` message.

Using the [`phoenix`](https://www.npmjs.com/package/phoenix) JavaScript client:

```js
import { Socket } from "phoenix";

const socket = new Socket("ws://raspberrypi.local:4000/socket");
socket.connect();

const channel = socket.channel("topic:sensors.kitchen");
channel.on("event", (event) => console.log(event.payload));
channel.join();

// You can also publish over the same connection:
channel.push("publish", { temperature: 22.0 });
```

Client libraries for Phoenix Channels exist for Python, Swift, Kotlin, Go, Rust and others.

### Web UI

Open `http://<PHX_HOST>:4000/` to see all topics, create new ones, and open a topic to watch its
events live.

---

## Security notes

eventbus is built for a **trusted network** such as a home LAN.

- It serves **plain HTTP**, with no TLS. Put a reverse proxy (Caddy, Traefik, nginx) in front of
  it if you expose it beyond your LAN.
- The API key protects **HTTP publishing only**. WebSocket subscribing and publishing, and the web
  UI, are not authenticated.
- There is one shared API key and no user accounts.

---

## Image details

- **Base:** `debian:bookworm-slim`, running as the unprivileged `nobody` user
- **Runtime:** Elixir 1.18 on Erlang/OTP 27, packaged as an OTP release (no Elixir or Mix in the
  final image)
- **Port:** `4000`
- **Startup:** runs pending database migrations, then starts the server
- **Volumes:** none. All state lives in Postgres.

## Source

https://github.com/altyaper/eventbus
