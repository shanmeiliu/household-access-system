.PHONY: fmt test vet build run check

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
