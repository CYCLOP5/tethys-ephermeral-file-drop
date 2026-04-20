// Package auth implements JWT-based authentication for the upload endpoint.
// Downloads are unauthenticated but guarded by a 256-bit random share token.
package auth

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// ErrUnauthorized is the only error callers need to differentiate.
var ErrUnauthorized = errors.New("unauthorized")

// Verifier validates bearer tokens.
type Verifier struct {
	secret []byte
}

// NewHS256 builds an HS256 JWT verifier with the given shared secret.
func NewHS256(secret []byte) *Verifier { return &Verifier{secret: secret} }

// Claims we extract. In a real deployment, issuer/audience would be checked.
type Claims struct {
	Subject string `json:"sub"`
	jwt.RegisteredClaims
}

// Verify parses and validates the bearer token from the Authorization header.
func (v *Verifier) Verify(h http.Header) (*Claims, error) {
	raw := strings.TrimPrefix(h.Get("Authorization"), "Bearer ")
	if raw == "" || raw == h.Get("Authorization") {
		return nil, ErrUnauthorized
	}
	claims := &Claims{}
	tok, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		if t.Method.Alg() != jwt.SigningMethodHS256.Alg() {
			return nil, fmt.Errorf("unexpected alg %q", t.Method.Alg())
		}
		return v.secret, nil
	})
	if err != nil || !tok.Valid {
		return nil, ErrUnauthorized
	}
	if claims.ExpiresAt != nil && claims.ExpiresAt.Before(time.Now()) {
		return nil, ErrUnauthorized
	}
	return claims, nil
}

// Issue is a convenience for testing and for the CLI tooling.
func (v *Verifier) Issue(subject string, ttl time.Duration) (string, error) {
	claims := Claims{
		Subject: subject,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return tok.SignedString(v.secret)
}
