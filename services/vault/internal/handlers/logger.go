package handlers

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5/middleware"
	"github.com/rs/zerolog/log"
)

// logger is a zerolog-backed chi middleware.
func logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		start := time.Now()
		defer func() {
			log.Info().
				Str("method", r.Method).
				Str("path", r.URL.Path).
				Int("status", ww.Status()).
				Dur("took", time.Since(start)).
				Str("remote_ip", r.RemoteAddr).
				Str("request_id", middleware.GetReqID(r.Context())).
				Msg("http")
		}()
		next.ServeHTTP(ww, r)
	})
}
