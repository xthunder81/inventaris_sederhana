package config

import (
	"reflect"
	"testing"
)

func TestLoadUsesSeparateLocalAPIPortAndWebOrigins(t *testing.T) {
	t.Setenv("JWT_SECRET", "01234567890123456789012345678901")
	t.Setenv("HTTP_ADDR", "")
	t.Setenv("CORS_ALLOWED_ORIGINS", "")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}

	if cfg.HTTPAddress != "127.0.0.1:8081" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, "127.0.0.1:8081")
	}
	wantOrigins := []string{
		"http://localhost:8080",
		"http://127.0.0.1:8080",
		"http://localhost:5173",
		"http://127.0.0.1:5173",
	}
	if !reflect.DeepEqual(cfg.CORSOrigins, wantOrigins) {
		t.Fatalf("CORSOrigins = %#v, want %#v", cfg.CORSOrigins, wantOrigins)
	}
}

func TestLoadKeepsExplicitHTTPAddressAndCORSOrigins(t *testing.T) {
	t.Setenv("JWT_SECRET", "01234567890123456789012345678901")
	t.Setenv("HTTP_ADDR", "127.0.0.1:9090")
	t.Setenv("CORS_ALLOWED_ORIGINS", "https://school.example, http://localhost:4321")

	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}

	if cfg.HTTPAddress != "127.0.0.1:9090" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, "127.0.0.1:9090")
	}
	wantOrigins := []string{"https://school.example", "http://localhost:4321"}
	if !reflect.DeepEqual(cfg.CORSOrigins, wantOrigins) {
		t.Fatalf("CORSOrigins = %#v, want %#v", cfg.CORSOrigins, wantOrigins)
	}
}
