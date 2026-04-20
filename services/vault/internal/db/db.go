// Package db wraps pgx with the small set of queries Vault actually needs.
package db

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/tethys-system/vault/internal/model"
)

// ErrNotFound is returned when a lookup by token/id misses.
var ErrNotFound = errors.New("not found")

// ErrExhausted is returned when the download budget is zero or expired.
var ErrExhausted = errors.New("link exhausted or expired")

// New opens a connection pool and verifies connectivity.
func New(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}
	cfg.MaxConns = 10
	cfg.MinConns = 1
	cfg.MaxConnIdleTime = 5 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, err
	}

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	if err := pool.Ping(pingCtx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return pool, nil
}

// Migrate creates the schema idempotently. For production, switch to a
// proper migration tool (goose, golang-migrate) and run it out-of-band.
func Migrate(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
CREATE TABLE IF NOT EXISTS files (
    id                  UUID        PRIMARY KEY,
    s3_key              TEXT        NOT NULL UNIQUE,
    size_bytes          BIGINT      NOT NULL,
    sha256              TEXT        NOT NULL DEFAULT '',
    download_token      TEXT        NOT NULL UNIQUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    max_downloads       INT         NOT NULL,
    remaining_downloads INT         NOT NULL
);
CREATE INDEX IF NOT EXISTS files_expires_at_idx     ON files (expires_at);
CREATE INDEX IF NOT EXISTS files_remaining_idx      ON files (remaining_downloads);
CREATE INDEX IF NOT EXISTS files_exhausted_idx      ON files (expires_at, remaining_downloads);

CREATE TABLE IF NOT EXISTS access_log (
    id         BIGSERIAL PRIMARY KEY,
    file_id    UUID      NOT NULL,
    action     TEXT      NOT NULL,
    ip         INET,
    user_agent TEXT,
    at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS access_log_file_idx ON access_log (file_id);
`)
	return err
}

// Repo is the narrow interface the handlers use; keeps tests simple.
type Repo struct{ Pool *pgxpool.Pool }

// NewRepo wraps a pool.
func NewRepo(pool *pgxpool.Pool) *Repo { return &Repo{Pool: pool} }

// InsertFile records the metadata for a new upload intent.
func (r *Repo) InsertFile(ctx context.Context, f *model.File) error {
	_, err := r.Pool.Exec(ctx, `
INSERT INTO files (id, s3_key, size_bytes, download_token, expires_at, max_downloads, remaining_downloads)
VALUES ($1,$2,$3,$4,$5,$6,$6)
`, f.ID, f.S3Key, f.SizeBytes, f.DownloadToken, f.ExpiresAt, f.MaxDownloads)
	return err
}

// ConsumeByToken atomically decrements remaining_downloads and returns the
// row if it is still valid. Uses FOR UPDATE SKIP LOCKED so repeated polls
// from the same client never spin on a row another request has already
// grabbed.
func (r *Repo) ConsumeByToken(ctx context.Context, token string) (*model.File, error) {
	tx, err := r.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var f model.File
	err = tx.QueryRow(ctx, `
SELECT id, s3_key, size_bytes, expires_at, max_downloads, remaining_downloads
FROM files
WHERE download_token = $1
  AND expires_at > now()
  AND remaining_downloads > 0
FOR UPDATE SKIP LOCKED
`, token).Scan(&f.ID, &f.S3Key, &f.SizeBytes, &f.ExpiresAt, &f.MaxDownloads, &f.RemainingDownloads)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrExhausted
		}
		return nil, err
	}

	_, err = tx.Exec(ctx, `
UPDATE files
SET remaining_downloads = remaining_downloads - 1
WHERE id = $1
`, f.ID)
	if err != nil {
		return nil, err
	}
	f.RemainingDownloads-- // reflect the decrement to the caller

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &f, nil
}

// LogAccess appends an audit row (best effort; never blocks a response).
func (r *Repo) LogAccess(ctx context.Context, fileID, action, ip, ua string) {
	_, _ = r.Pool.Exec(ctx, `
INSERT INTO access_log (file_id, action, ip, user_agent) VALUES ($1,$2,NULLIF($3,'')::inet,$4)
`, fileID, action, ip, ua)
}
