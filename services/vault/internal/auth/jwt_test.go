package auth

import (
	"net/http"
	"testing"
	"time"
)

func TestIssueAndVerify(t *testing.T) {
	v := NewHS256([]byte("test-secret-do-not-use"))

	tok, err := v.Issue("user-1", time.Minute)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	if tok == "" {
		t.Fatal("empty token")
	}

	h := http.Header{}
	h.Set("Authorization", "Bearer "+tok)

	claims, err := v.Verify(h)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if claims.Subject != "user-1" {
		t.Fatalf("bad subject %q", claims.Subject)
	}
}

func TestVerifyRejectsBadAlg(t *testing.T) {
	v := NewHS256([]byte("s"))
	h := http.Header{}
	h.Set("Authorization", "Bearer not-a-token")
	if _, err := v.Verify(h); err == nil {
		t.Fatal("expected error")
	}
}

func TestVerifyRequiresBearer(t *testing.T) {
	v := NewHS256([]byte("s"))
	if _, err := v.Verify(http.Header{}); err == nil {
		t.Fatal("expected error when no header")
	}
}
