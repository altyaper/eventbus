# No `# syntax=docker/dockerfile:1` pin here on purpose: resolving that
# frontend image requires a direct TLS request to registry-1.docker.io that
# times out behind the Bloomberg proxy. Omitting it makes BuildKit use its
# own bundled frontend (same or newer version, no network call) instead.

# Build this directly on the target machine (e.g. `docker compose build` run
# on the Raspberry Pi itself) and Docker will automatically pick the right
# arch (arm64 or armv7) — no cross-compilation needed.

ARG ELIXIR_VERSION=1.18.5
ARG OTP_VERSION=27.3.4.18
ARG DEBIAN_VERSION=bookworm-20260918-slim
# The rolling, heavily-cached tag, not the dated one above — the hexpm/elixir
# builder needs an exact dated tag to match its own build, but the plain
# debian runner doesn't, and the dated tag has been unreliable to fetch.
ARG RUNNER_DEBIAN_VERSION=bookworm-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${RUNNER_DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y build-essential git ca-certificates libncurses6 \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Optional extra trusted CA for building behind a TLS-intercepting corporate
# proxy (e.g. on a dev machine, not needed on the Pi itself). The glob makes
# this a no-op when the file isn't present: `make docker-build` copies it in
# from ~/.cache/elixir-ca/os-trust.crt first (must be the full root+intercepting
# chain, not just the intercepting cert, or verification still fails).
# update-ca-certificates covers `mix local.hex`/`local.rebar`, which ignore
# HEX_CACERTS_PATH; it's set too since `mix deps.get` does respect it.
COPY docker/extra-ca.cr[t] /usr/local/share/ca-certificates/
RUN update-ca-certificates
ENV HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

# Compile first: Phoenix 1.8's colocated-CSS/JS feature generates files
# under phoenix-colocated/ during `mix compile`, and the Tailwind build run
# by `assets.deploy` needs those to already exist.
RUN mix compile

RUN mix assets.deploy

COPY config/runtime.exs config/

RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV="prod"

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/eventbus ./
COPY --chown=nobody:root --chmod=755 docker/entrypoint.sh /app/bin/docker-entrypoint.sh

USER nobody

EXPOSE 4000

CMD ["/app/bin/docker-entrypoint.sh"]
