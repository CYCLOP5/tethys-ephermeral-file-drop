SHELL := /bin/bash

BIN       ?= vault
IMAGE     ?= tethys/vault
TAG       ?= dev

.PHONY: build run test lint docker-build docker-run dev clean

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/$(BIN) ./cmd/server

test:
	go test -race -count=1 ./...

lint:
	golangci-lint run ./...

docker-build:
	docker build -t $(IMAGE):$(TAG) .

run:
	DATABASE_URL=postgres://tethys:tethys@localhost:5432/tethys?sslmode=disable \
	S3_BUCKET=tethys-dev \
	AWS_REGION=us-east-1 \
	JWT_SECRET=dev-secret-do-not-use \
	go run ./cmd/server

dev:
	docker compose up --build

clean:
	rm -rf bin/
