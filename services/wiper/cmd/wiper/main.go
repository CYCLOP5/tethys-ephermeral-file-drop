// Package main is the Tethys Wiper entry point.
//
// Wiper runs as a Kubernetes CronJob every few minutes. Each invocation:
//
//  1. BEGIN a serializable txn
//  2. SELECT a batch of expired/exhausted files FOR UPDATE SKIP LOCKED
//  3. S3 DeleteObject each one
//  4. DELETE rows, COMMIT
//
// The SKIP LOCKED clause makes it safe for two or more Wiper pods to run
// concurrently without duplicating work or deadlocking each other.
package main

import (
	"context"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
)

func main() {
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	log.Logger = log.Output(os.Stdout).With().Timestamp().Str("service", "wiper").Logger()

	dsn := os.Getenv("DATABASE_URL")
	bucket := os.Getenv("S3_BUCKET")
	region := getenv("AWS_REGION", "us-east-1")
	batchStr := getenv("BATCH_SIZE", "100")
	batchSize, err := strconv.Atoi(batchStr)
	if err != nil || batchSize <= 0 || batchSize > 1000 {
		log.Fatal().Str("batch", batchStr).Msg("BATCH_SIZE must be between 1 and 1000")
	}

	if dsn == "" || bucket == "" {
		log.Fatal().Msg("DATABASE_URL and S3_BUCKET are required")
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatal().Err(err).Msg("pgxpool")
	}
	defer pool.Close()

	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		log.Fatal().Err(err).Msg("aws config")
	}
	s3c := s3.NewFromConfig(cfg)

	start := time.Now()
	purged, failed, err := purgeOnce(ctx, pool, s3c, bucket, batchSize)
	log.Info().
		Int("purged", purged).
		Int("failed", failed).
		Dur("took", time.Since(start)).
		Err(err).
		Msg("wiper run complete")
	if err != nil {
		os.Exit(1)
	}
}

// purgeOnce grabs a batch of expired/exhausted rows, deletes each object from
// S3, and then deletes the rows. Returns (purged, failed, err). A per-object
// failure is logged and counted but does NOT fail the batch.
func purgeOnce(ctx context.Context, pool *pgxpool.Pool, s3c *s3.Client, bucket string, batch int) (int, int, error) {
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.Serializable})
	if err != nil {
		return 0, 0, err
	}
	defer tx.Rollback(ctx)

	rows, err := tx.Query(ctx, `
SELECT id, s3_key
FROM   files
WHERE  expires_at <= now() OR remaining_downloads <= 0
ORDER  BY expires_at
LIMIT  $1
FOR UPDATE SKIP LOCKED
`, batch)
	if err != nil {
		return 0, 0, err
	}

	type row struct{ id, key string }
	var toDelete []row
	for rows.Next() {
		var r row
		if err := rows.Scan(&r.id, &r.key); err != nil {
			rows.Close()
			return 0, 0, err
		}
		toDelete = append(toDelete, r)
	}
	rows.Close()

	if len(toDelete) == 0 {
		return 0, 0, tx.Commit(ctx)
	}

	purged := 0
	failed := 0
	deletedIDs := make([]string, 0, len(toDelete))

	for _, r := range toDelete {
		_, err := s3c.DeleteObject(ctx, &s3.DeleteObjectInput{
			Bucket: aws.String(bucket),
			Key:    aws.String(r.key),
		})
		if err != nil {
			// Treat NoSuchKey as already-gone; everything else is a failure we
			// intentionally leave in the DB so the next run retries.
			if isAlreadyGone(err) {
				deletedIDs = append(deletedIDs, r.id)
				purged++
				continue
			}
			failed++
			log.Error().Err(err).Str("key", r.key).Msg("s3 delete failed")
			continue
		}
		deletedIDs = append(deletedIDs, r.id)
		purged++
	}

	if len(deletedIDs) > 0 {
		_, err = tx.Exec(ctx, `DELETE FROM files WHERE id = ANY($1::uuid[])`, deletedIDs)
		if err != nil {
			return purged, failed, err
		}
	}

	return purged, failed, tx.Commit(ctx)
}

// isAlreadyGone returns true if the S3 error indicates the object is already
// deleted (so we can safely drop the DB row and move on).
func isAlreadyGone(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "NoSuchKey") || strings.Contains(msg, "status code: 404")
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
