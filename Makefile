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

.PHONY: help setup install \
        start server console \
        db-create db-migrate db-rollback db-reset db-status db-console \
        db-up db-down db-stop db-logs \
        build test format check routes publish clean

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
