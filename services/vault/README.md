# Vault Service

The Tethys Vault is a small Go REST API. It never touches file bytes; it
mints short-lived presigned S3 URLs and keeps metadata in Postgres.

## Endpoints

| Method | Path                          | Auth  | Purpose                                  |
| ------ | ----------------------------- | ----- | ---------------------------------------- |
| GET    | `/healthz`                    | none  | Liveness probe                           |
| GET    | `/readyz`                     | none  | Readiness probe                          |
| POST   | `/api/v1/uploads`             | JWT   | Return presigned PUT + share token       |
| GET    | `/api/v1/downloads/{token}`   | none  | Atomically consume a share token and return presigned GET |

Downloads are deliberately unauthenticated - the share token is a 256-bit
random value and is the only thing that gates access. The passphrase that
actually decrypts the blob lives in the URL fragment in the client and is
never seen by the server.

## Environment

| Variable          | Required | Default   | Description                         |
| ----------------- | -------- | --------- | ----------------------------------- |
| `DATABASE_URL`    | yes      |           | `postgres://...?sslmode=require`    |
| `S3_BUCKET`       | yes      |           | Encrypted file bucket               |
| `AWS_REGION`      | no       | us-east-1 |                                     |
| `JWT_SECRET`      | yes      |           | HS256 shared secret                 |
| `MAX_TTL_SECONDS` | no       | 604800    | Cap TTL clients can request         |
| `VAULT_ADDR`      | no       | :8080     | Listen address                      |

## Local dev

```bash
make run        # needs a local postgres and S3 (or MinIO)
make test
make docker-build
```

See the repo-root `docs/runbook.md` for container registry and Kubernetes
deployment notes.
