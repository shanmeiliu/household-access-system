DB_NAME ?= household_access
DB_USER ?= postgres

# Default: use the PostgreSQL service defined in docker-compose.yml.
#
# To reuse an existing container:
# make db-legacy DB_EXEC="docker exec -i my-postgres"
DB_EXEC ?= docker compose exec -T postgres
DB_EXEC_IT ?= docker compose exec postgres

.PHONY: fmt test vet build run check \
	db-up db-down db-psql db-legacy db-verify-legacy \
	db-new-schema db-verify-new-schema db-test-new-schema-constraints \
	db-backfill db-verify-backfill db-check-backfill-idempotency

fmt:
	go fmt ./...

test:
	go test ./...

vet:
	go vet ./...

build:
	go build ./cmd/api

run:
	go run ./cmd/api

check: fmt test vet build

db-up:
	docker compose up -d

db-down:
	docker compose down

db-psql:
	$(DB_EXEC_IT) \
		psql -U $(DB_USER) -d $(DB_NAME)

db-legacy:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< migrations/001_legacy_schema.sql

db-verify-legacy:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< scripts/verify-legacy.sql

db-new-schema:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< migrations/002_new_schema.sql

db-verify-new-schema:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< scripts/verify-new-schema.sql

db-test-new-schema-constraints:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< scripts/test-new-schema-constraints.sql

db-backfill:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< migrations/003_backfill.sql

db-verify-backfill:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< scripts/verify-backfill.sql

db-check-backfill-idempotency:
	$(DB_EXEC) \
		psql -v ON_ERROR_STOP=1 -U $(DB_USER) -d $(DB_NAME) \
		< scripts/test-backfill-idempotency.sql
