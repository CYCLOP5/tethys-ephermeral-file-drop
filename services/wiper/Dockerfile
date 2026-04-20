# syntax=docker/dockerfile:1.6
FROM golang:1.22-bookworm AS build
WORKDIR /src

COPY go.mod ./
RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    go mod download

COPY . .

RUN --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/go/pkg/mod \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags "-s -w -buildid=" -o /out/wiper ./cmd/wiper

FROM gcr.io/distroless/static-debian12:nonroot AS runtime
WORKDIR /
COPY --from=build /out/wiper /wiper

USER nonroot:nonroot
ENTRYPOINT ["/wiper"]
