package config

import "testing"

func TestLoadDefaultHTTPAddress(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", "")
	t.Setenv("DATABASE_URL", "postgres://example")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.HTTPAddress != ":8080" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, ":8080")
	}
}

func TestLoadCustomHTTPAddress(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", ":9090")
	t.Setenv("DATABASE_URL", "postgres://example")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.HTTPAddress != ":9090" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, ":9090")
	}
}

func TestLoadMissingDatabaseURL(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", ":9090")
	t.Setenv("DATABASE_URL", "")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want error")
	}
}

func TestLoadWhitespaceOnlyDatabaseURL(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", ":9090")
	t.Setenv("DATABASE_URL", " \t\n ")

	if _, err := Load(); err == nil {
		t.Fatal("Load() error = nil, want error")
	}
}

func TestLoadTrimsEnvironmentValues(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", " :9090 ")
	t.Setenv("DATABASE_URL", " postgres://example ")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.HTTPAddress != ":9090" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, ":9090")
	}

	if cfg.DatabaseURL != "postgres://example" {
		t.Fatalf("DatabaseURL = %q, want %q", cfg.DatabaseURL, "postgres://example")
	}
}

func TestLoadWhitespaceOnlyHTTPAddressUsesDefault(t *testing.T) {
	t.Setenv("HTTP_ADDRESS", " \t\n ")
	t.Setenv("DATABASE_URL", "postgres://example")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() error = %v", err)
	}

	if cfg.HTTPAddress != ":8080" {
		t.Fatalf("HTTPAddress = %q, want %q", cfg.HTTPAddress, ":8080")
	}
}
