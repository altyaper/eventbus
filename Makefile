# eventbus — common developer tasks.
# Run `make` or `make help` to see everything available.
#
# Phoenix app on http://localhost:4000
# See docs/plans/2026-10-01-eventbus-design.md for the design.

.DEFAULT_GOAL := help

# Hex/mix can't complete its TLS handshake through the Bloomberg proxy
# without this CA bundle — needed for any command that hits the network
# (deps.get, archive.install, hex.*).
HEX_CACERTS_PATH ?= $(HOME)/.cache/elixir-ca/os-trust.crt
export HEX_CACERTS_PATH

MIX          := mix
PORT         ?= 4000
# Reuses the shared Postgres container from the changologs setup (see its
# docs/SETUP.md) — eventbus just adds its own database on the same instance.
PG_CONTAINER ?= changologs-postgres
PG_IMAGE     ?= pgvector/pgvector:pg16
API_KEY      ?= dev-secret
TOPIC        ?= example
PAYLOAD      ?= {"hello":"world"}

# Only present on machines building behind a TLS-intercepting corporate
# proxy. Must be the full trust bundle (root + intercepting CA), not just
# the intercepting cert alone — see Dockerfile for why `docker-build`
# stages a copy of this.
EXTRA_CA_SRC ?= $(HOME)/.cache/elixir-ca/os-trust.crt

.PHONY: help setup install \
        start server console \
        db-create db-migrate db-rollback db-reset db-status db-console \
        db-up db-down db-stop db-logs \
        build test format check routes publish clean \
        docker-build docker-up docker-down docker-logs docker-ps

## ---------------------------------------------------------------------------
## Help
## ---------------------------------------------------------------------------

help: ## Show this help
	@echo "eventbus — available targets:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo ""

## ---------------------------------------------------------------------------
## Setup
## ---------------------------------------------------------------------------

setup: db-up ## Full first-time setup: start Postgres, install deps, create+migrate DB, build assets
	$(MIX) setup
	@echo ""
	@echo "Setup complete. Start the app with: make start"

install: ## mix deps.get
	$(MIX) deps.get

## ---------------------------------------------------------------------------
## Running the app
## ---------------------------------------------------------------------------

start: ## Run the Phoenix server (http://localhost:4000, override with PORT=)
	PORT=$(PORT) $(MIX) phx.server

server: start ## Alias for start

console: ## Start an IEx session with the app and server running
	PORT=$(PORT) iex -S mix phx.server

## ---------------------------------------------------------------------------
## Database
## ---------------------------------------------------------------------------

db-create: ## Create the database
	$(MIX) ecto.create

db-migrate: ## Run pending migrations
	$(MIX) ecto.migrate

db-rollback: ## Roll back the last migration (STEP=n for more)
	$(MIX) ecto.rollback --step $(or $(STEP),1)

db-reset: ## Drop, recreate and migrate (destroys local data)
	$(MIX) ecto.reset

db-status: ## Show migration status
	$(MIX) ecto.migrations

db-console: ## Open a psql session against the dev database
	docker exec -it $(PG_CONTAINER) psql -U postgres -d eventbus_dev

## --- Postgres via Docker, shared with changologs ---------------------------

db-up: ## Start the shared Postgres container if it isn't already running
	@docker start $(PG_CONTAINER) 2>/dev/null || \
	docker run -d --name $(PG_CONTAINER) \
		-e POSTGRES_USER=postgres \
		-e POSTGRES_PASSWORD=postgres \
		-p 5432:5432 \
		$(PG_IMAGE)

db-stop: ## Stop the shared Postgres container
	docker stop $(PG_CONTAINER)

db-down: db-stop ## Alias for db-stop (does not remove the container or its data)

db-logs: ## Tail the Postgres container logs
	docker logs -f $(PG_CONTAINER)

## ---------------------------------------------------------------------------
## Building, testing and quality
## ---------------------------------------------------------------------------

build: ## Build frontend assets (esbuild + tailwind)
	$(MIX) assets.build

test: ## Run the test suite (TEST=path/to/some_test.exs for one file)
	$(MIX) test $(TEST)

format: ## Format the codebase
	$(MIX) format

check: ## Strict compile, unused deps check, format, and full test suite
	$(MIX) precommit

## ---------------------------------------------------------------------------
## Misc
## ---------------------------------------------------------------------------

routes: ## Print Phoenix routes
	$(MIX) phx.routes

publish: ## Publish a test event (TOPIC=name PAYLOAD='{"json":true}')
	curl -i http://localhost:$(PORT)/api/topics/$(TOPIC)/events \
		-H "Authorization: Bearer $(API_KEY)" \
		-H "Content-Type: application/json" \
		-d '$(PAYLOAD)'

clean: ## Remove build output and caches
	rm -rf _build priv/static/assets priv/static/cache_manifest.json

## ---------------------------------------------------------------------------
## Docker (full app + its own Postgres, see docker-compose.yml)
## ---------------------------------------------------------------------------

# Something in this machine's environment sets DOCKER_DEFAULT_PLATFORM=
# linux/amd64 outside any dotfile we could find, which silently builds under
# Rosetta emulation on this arm64 Mac and causes flaky BEAM JIT crashes.
# Force native arch here regardless of that ambient setting.
DOCKER_DEFAULT_PLATFORM := linux/arm64
export DOCKER_DEFAULT_PLATFORM

docker-build: ## Build the app image (stages an extra CA cert if present, see Dockerfile)
	@test -f "$(EXTRA_CA_SRC)" && cp "$(EXTRA_CA_SRC)" docker/extra-ca.crt \
		|| rm -f docker/extra-ca.crt
	docker compose build

docker-up: docker-build ## Build and start the app + its own Postgres (needs .env, see docker.env.example)
	docker compose up -d

docker-down: ## Stop and remove the app + its Postgres containers
	docker compose down

docker-logs: ## Tail the app container logs
	docker compose logs -f app

docker-ps: ## Show status of the compose services
	docker compose ps
