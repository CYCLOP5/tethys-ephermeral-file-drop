// Package model holds the domain types shared across the service.
package model

import "time"

// File is the metadata Vault keeps about each encrypted blob in S3.
// The ciphertext itself is never seen by the server.
type File struct {
	ID                 string    `json:"id"`
	S3Key              string    `json:"s3_key"`
	SizeBytes          int64     `json:"size_bytes"`
	SHA256             string    `json:"sha256"`
	CreatedAt          time.Time `json:"created_at"`
	ExpiresAt          time.Time `json:"expires_at"`
	MaxDownloads       int       `json:"max_downloads"`
	RemainingDownloads int       `json:"remaining_downloads"`
	DownloadToken      string    `json:"-"` // returned once, never echoed back
}

// UploadRequest is the client's intent to upload.
type UploadRequest struct {
	SizeBytes    int64 `json:"size_bytes"`
	TTLSeconds   int   `json:"ttl_seconds"`
	MaxDownloads int   `json:"max_downloads"`
}

// UploadResponse gives the client a presigned PUT URL plus a share token.
type UploadResponse struct {
	UploadID       string    `json:"upload_id"`
	PresignedPutURL string   `json:"presigned_put_url"`
	DownloadToken  string    `json:"download_token"`
	ExpiresAt      time.Time `json:"expires_at"`
}

// DownloadResponse tells the client where to fetch the ciphertext.
type DownloadResponse struct {
	PresignedGetURL string    `json:"presigned_get_url"`
	ExpiresAt       time.Time `json:"expires_at"`
	RemainingUses   int       `json:"remaining_uses"`
}
