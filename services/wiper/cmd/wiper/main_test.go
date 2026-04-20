package main

import (
	"errors"
	"testing"
)

func TestIsAlreadyGone(t *testing.T) {
	cases := []struct {
		in   error
		want bool
	}{
		{nil, false},
		{errors.New("random"), false},
		{errors.New("NoSuchKey: the specified key does not exist"), true},
		{errors.New("api error, status code: 404"), true},
		{errors.New("InternalError"), false},
	}
	for _, c := range cases {
		if got := isAlreadyGone(c.in); got != c.want {
			t.Fatalf("isAlreadyGone(%v) = %v, want %v", c.in, got, c.want)
		}
	}
}

func TestGetenvFallback(t *testing.T) {
	t.Setenv("TETHYS_TEST_X", "")
	if v := getenv("TETHYS_TEST_X", "hello"); v != "hello" {
		t.Fatalf("fallback failed: %q", v)
	}
	t.Setenv("TETHYS_TEST_X", "world")
	if v := getenv("TETHYS_TEST_X", "hello"); v != "world" {
		t.Fatalf("override failed: %q", v)
	}
}
