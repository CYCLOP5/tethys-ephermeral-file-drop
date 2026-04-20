package main

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Addr        string
	DatabaseURL string
	AWSRegion   string
	S3Bucket    string
	JWTSecret   []byte
	MaxTTL      time.Duration
}

func LoadConfig() (Config, error) {
	cfg := Config{
		Addr:        getenv("VAULT_ADDR", ":8080"),
		DatabaseURL: os.Getenv("DATABASE_URL"),
		AWSRegion:   getenv("AWS_REGION", "us-east-1"),
		S3Bucket:    os.Getenv("S3_BUCKET"),
	}

	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		return cfg, fmt.Errorf("JWT_SECRET is required")
	}
	cfg.JWTSecret = []byte(secret)

	if cfg.DatabaseURL == "" {
		return cfg, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.S3Bucket == "" {
		return cfg, fmt.Errorf("S3_BUCKET is required")
	}

	ttlStr := getenv("MAX_TTL_SECONDS", "604800") // 7 days
	ttlSec, err := strconv.Atoi(ttlStr)
	if err != nil || ttlSec <= 0 {
		return cfg, fmt.Errorf("MAX_TTL_SECONDS must be a positive integer")
	}
	cfg.MaxTTL = time.Duration(ttlSec) * time.Second

	return cfg, nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
