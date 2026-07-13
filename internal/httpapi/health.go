package httpapi

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

const readinessTimeout = 2 * time.Second

type statusResponse struct {
	Status string `json:"status"`
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, statusResponse{Status: "ok"}, s.logger)
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), readinessTimeout)
	defer cancel()

	if err := s.db.Ping(ctx); err != nil {
		s.logger.Warn("database readiness check failed", slog.Any("error", err))
		writeJSON(w, http.StatusServiceUnavailable, statusResponse{Status: "not_ready"}, s.logger)
		return
	}

	writeJSON(w, http.StatusOK, statusResponse{Status: "ready"}, s.logger)
}

func writeJSON(w http.ResponseWriter, status int, payload any, logger *slog.Logger) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)

	if err := json.NewEncoder(w).Encode(payload); err != nil && logger != nil {
		logger.Warn("failed to encode JSON response", slog.Any("error", err))
	}
}
