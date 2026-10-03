# Eventbus

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Running with Docker (e.g. on a Raspberry Pi)

```
cp docker.env.example .env
# edit .env: set SECRET_KEY_BASE (mix phx.gen.secret), PHX_HOST, EVENTBUS_API_KEY, POSTGRES_PASSWORD
docker compose up -d --build
```

Build this directly on the target machine so Docker picks the right CPU architecture
automatically (no cross-compilation needed). The app runs plain HTTP on the LAN
(`force_ssl` is disabled) and applies Ecto migrations automatically on startup.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
