// Package main is the entry point for the Tethys Vault service.
//
// Vault never sees plaintext. It only mints short-lived presigned S3 URLs
// and keeps metadata (id, sha256, size, TTL, remaining_downloads) in
// Postgres. File bytes are client-side encrypted (AES-256-GCM / PBKDF2)
// in the browser before hitting S3.
package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"

	"github.com/tethys-system/vault/internal/auth"
	"github.com/tethys-system/vault/internal/db"
	"github.com/tethys-system/vault/internal/handlers"
	"github.com/tethys-system/vault/internal/storage"
)

func main() {
	zerolog.TimeFieldFormat = zerolog.TimeFormatUnix
	log.Logger = log.Output(os.Stdout).With().Timestamp().Str("service", "vault").Logger()

	cfg, err := LoadConfig()
	if err != nil {
		log.Fatal().Err(err).Msg("config")
	}

	rootCtx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	pool, err := db.New(rootCtx, cfg.DatabaseURL)
	if err != nil {
		log.Fatal().Err(err).Msg("database connect")
	}
	defer pool.Close()

	if err := db.Migrate(rootCtx, pool); err != nil {
		log.Fatal().Err(err).Msg("database migrate")
	}

	s3c, err := storage.NewS3(rootCtx, cfg.AWSRegion, cfg.S3Bucket)
	if err != nil {
		log.Fatal().Err(err).Msg("s3 init")
	}

	jwtv := auth.NewHS256(cfg.JWTSecret)

	h := handlers.New(handlers.Deps{
		DB:     pool,
		S3:     s3c,
		JWT:    jwtv,
		MaxTTL: cfg.MaxTTL,
	})

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           h.Router(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       90 * time.Second,
	}

	go func() {
		log.Info().Str("addr", cfg.Addr).Msg("listening")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal().Err(err).Msg("http")
		}
	}()

	<-rootCtx.Done()
	log.Info().Msg("shutting down")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	_ = srv.Shutdown(shutdownCtx)
}
