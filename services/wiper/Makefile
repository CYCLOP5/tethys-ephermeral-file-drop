SHELL := /bin/bash

IMAGE ?= tethys/wiper
TAG   ?= dev

.PHONY: build test docker-build lint

build:
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/wiper ./cmd/wiper

test:
	go test -race -count=1 ./...

lint:
	golangci-lint run ./...

docker-build:
	docker build -t $(IMAGE):$(TAG) .
