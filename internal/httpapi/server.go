// Package httpapi contains the HTTP server for the API demo.
package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shanmeiliu/household-access-system/internal/auth"
)

type manageableProfilesService interface {
	ManageableProfiles(ctx context.Context, loginID uuid.UUID) (auth.ManageableProfiles, error)
}

// Server owns the HTTP server and shared dependencies for request handlers.
type Server struct {
	httpServer *http.Server
	db         *pgxpool.Pool
	auth       manageableProfilesService
	logger     *slog.Logger
}

// NewServer constructs the API HTTP server.
func NewServer(address string, database *pgxpool.Pool, authService *auth.Service, logger *slog.Logger) *Server {
	if logger == nil {
		logger = slog.Default()
	}

	server := &Server{
		db:     database,
		auth:   authService,
		logger: logger,
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", server.handleHealth)
	mux.HandleFunc("GET /ready", server.handleReady)
	mux.HandleFunc("GET /logins/{loginID}/manageable-profiles", server.handleManageableProfiles)

	server.httpServer = &http.Server{
		Addr:              address,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	return server
}

// ListenAndServe starts accepting HTTP requests.
func (s *Server) ListenAndServe() error {
	err := s.httpServer.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return http.ErrServerClosed
	}

	return err
}

// Shutdown gracefully stops the HTTP server.
func (s *Server) Shutdown(ctx context.Context) error {
	return s.httpServer.Shutdown(ctx)
}
