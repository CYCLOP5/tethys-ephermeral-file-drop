# Wiper Service

A one-shot Go binary that purges expired or exhausted files from S3 and the
Postgres metadata table. Deployed as a Kubernetes `CronJob` that runs every
5 minutes.

## Environment

| Variable       | Required | Default   | Description                      |
| -------------- | -------- | --------- | -------------------------------- |
| `DATABASE_URL` | yes      |           | `postgres://...?sslmode=require` |
| `S3_BUCKET`    | yes      |           | File bucket                      |
| `AWS_REGION`   | no       | us-east-1 |                                  |
| `BATCH_SIZE`   | no       | 100       | Rows per run (1-1000)            |

## Concurrency

Wiper uses `SELECT ... FOR UPDATE SKIP LOCKED` so that two or more instances
can run at the same time without stepping on each other. The CronJob's
`concurrencyPolicy` is `Forbid` by default anyway.

## Exit codes

- `0`: ran to completion (may have per-object failures logged)
- `1`: aborted due to an unrecoverable DB/AWS error
