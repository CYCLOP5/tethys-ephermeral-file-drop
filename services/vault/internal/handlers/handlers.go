// Package handlers implements the HTTP surface of the Vault service.
package handlers

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/rs/zerolog/log"

	"github.com/tethys-system/vault/internal/auth"
	"github.com/tethys-system/vault/internal/db"
	"github.com/tethys-system/vault/internal/model"
	"github.com/tethys-system/vault/internal/storage"
)

const (
	defaultUploadURLTTL   = 5 * time.Minute
	defaultDownloadURLTTL = 2 * time.Minute
	maxFileSize           = 100 * 1024 * 1024 // 100 MB (keeps free-tier S3 tiny)
)

// Deps is the handler dependency bundle.
type Deps struct {
	DB     *pgxpool.Pool
	S3     *storage.Client
	JWT    *auth.Verifier
	MaxTTL time.Duration
}

// API owns a repo and S3 client and wires up the router.
type API struct {
	repo   *db.Repo
	s3     *storage.Client
	jwt    *auth.Verifier
	maxTTL time.Duration
}

// New wires up the handler.
func New(d Deps) *API {
	return &API{
		repo:   db.NewRepo(d.DB),
		s3:     d.S3,
		jwt:    d.JWT,
		maxTTL: d.MaxTTL,
	}
}

// Router builds the chi mux.
func (a *API) Router() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(logger)

	r.Get("/healthz", a.health)
	r.Get("/readyz", a.health)

	r.Route("/api/v1", func(r chi.Router) {
		r.With(a.authn).Post("/uploads", a.createUpload)
		r.Get("/downloads/{token}", a.getDownload)
	})
	return r
}

func (a *API) health(w http.ResponseWriter, _ *http.Request) {
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// authn is a middleware that enforces a valid JWT for mutating endpoints.
func (a *API) authn(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, err := a.jwt.Verify(r.Header); err != nil {
			writeErr(w, http.StatusUnauthorized, "unauthorized")
			return
		}
		next.ServeHTTP(w, r)
	})
}

// createUpload consumes an UploadRequest and returns a presigned PUT URL plus
// the single share token.
func (a *API) createUpload(w http.ResponseWriter, r *http.Request) {
	var req model.UploadRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<16)).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.SizeBytes <= 0 || req.SizeBytes > maxFileSize {
		writeErr(w, http.StatusBadRequest,
			fmt.Sprintf("size_bytes must be between 1 and %d", maxFileSize))
		return
	}
	ttl := time.Duration(req.TTLSeconds) * time.Second
	if ttl <= 0 || ttl > a.maxTTL {
		ttl = a.maxTTL
	}
	if req.MaxDownloads < 1 {
		req.MaxDownloads = 1
	}
	if req.MaxDownloads > 100 {
		req.MaxDownloads = 100
	}

	id, err := randomID()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "id gen")
		return
	}
	token, err := randomToken()
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "token gen")
		return
	}

	key := "files/" + id
	expiresAt := time.Now().Add(ttl).UTC()

	file := &model.File{
		ID:                 id,
		S3Key:              key,
		SizeBytes:          req.SizeBytes,
		DownloadToken:      token,
		CreatedAt:          time.Now().UTC(),
		ExpiresAt:          expiresAt,
		MaxDownloads:       req.MaxDownloads,
		RemainingDownloads: req.MaxDownloads,
	}
	if err := a.repo.InsertFile(r.Context(), file); err != nil {
		log.Error().Err(err).Msg("insert file")
		writeErr(w, http.StatusInternalServerError, "persist")
		return
	}

	putURL, err := a.s3.PresignPut(r.Context(), key, req.SizeBytes, defaultUploadURLTTL)
	if err != nil {
		log.Error().Err(err).Msg("presign put")
		writeErr(w, http.StatusInternalServerError, "presign")
		return
	}

	a.repo.LogAccess(r.Context(), id, "upload_init", r.RemoteAddr, r.UserAgent())
	writeJSON(w, http.StatusCreated, model.UploadResponse{
		UploadID:        id,
		PresignedPutURL: putURL,
		DownloadToken:   token,
		ExpiresAt:       expiresAt,
	})
}

// getDownload atomically decrements the remaining_downloads counter and
// returns a presigned GET URL if the link is still valid.
func (a *API) getDownload(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	if len(token) < 32 {
		writeErr(w, http.StatusBadRequest, "bad token")
		return
	}

	file, err := a.repo.ConsumeByToken(r.Context(), token)
	if err != nil {
		if errors.Is(err, db.ErrExhausted) {
			writeErr(w, http.StatusGone, "link expired or exhausted")
			return
		}
		log.Error().Err(err).Msg("consume token")
		writeErr(w, http.StatusInternalServerError, "server error")
		return
	}

	getURL, err := a.s3.PresignGet(r.Context(), file.S3Key, defaultDownloadURLTTL)
	if err != nil {
		log.Error().Err(err).Msg("presign get")
		writeErr(w, http.StatusInternalServerError, "presign")
		return
	}

	a.repo.LogAccess(r.Context(), file.ID, "download", r.RemoteAddr, r.UserAgent())
	writeJSON(w, http.StatusOK, model.DownloadResponse{
		PresignedGetURL: getURL,
		ExpiresAt:       time.Now().Add(defaultDownloadURLTTL).UTC(),
		RemainingUses:   file.RemainingDownloads,
	})
}

// --- helpers ---

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func randomID() (string, error) {
	var buf [16]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", err
	}
	// UUIDv4 format without external deps.
	buf[6] = (buf[6] & 0x0f) | 0x40
	buf[8] = (buf[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		buf[0:4], buf[4:6], buf[6:8], buf[8:10], buf[10:16]), nil
}

func randomToken() (string, error) {
	var buf [32]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf[:]), nil
}

