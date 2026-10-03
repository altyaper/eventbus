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
printed in the logs until setup is done (`docker compose logs app`). Afterwards the
superadmin can copy it from the user menu. The same key authorizes
`POST /api/topics/:name/events`.

Build this directly on the target machine so Docker picks the right CPU architecture
automatically (no cross-compilation needed). The app runs plain HTTP on the LAN
(`force_ssl` is disabled) and applies Ecto migrations automatically on startup.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
