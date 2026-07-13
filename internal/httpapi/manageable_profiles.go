package httpapi

import (
	"context"
	"errors"
	"log/slog"
	"net/http"

	"github.com/google/uuid"
	"github.com/shanmeiliu/household-access-system/internal/auth"
)

type manageableProfilesResponse struct {
	LoginID     string                    `json:"login_id"`
	HouseholdID string                    `json:"household_id"`
	Profiles    []manageableProfileObject `json:"profiles"`
}

type manageableProfileObject struct {
	ID          string `json:"id"`
	DisplayName string `json:"display_name"`
	Role        string `json:"role"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func (s *Server) handleManageableProfiles(w http.ResponseWriter, r *http.Request) {
	loginID, err := uuid.Parse(r.PathValue("loginID"))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{Error: "invalid_login_id"}, s.logger)
		return
	}

	result, err := s.auth.ManageableProfiles(r.Context(), loginID)
	if err != nil {
		if errors.Is(err, auth.ErrLoginNotFound) {
			writeJSON(w, http.StatusNotFound, errorResponse{Error: "login_not_found"}, s.logger)
			return
		}

		s.logger.Error(
			"manageable profiles request failed",
			slog.String("endpoint", "GET /logins/{loginID}/manageable-profiles"),
			slog.String("login_id", loginID.String()),
			slog.Any("error", err),
		)
		writeJSON(w, http.StatusInternalServerError, errorResponse{Error: "internal_error"}, s.logger)
		return
	}

	writeJSON(w, http.StatusOK, toManageableProfilesResponse(result), s.logger)
}

func toManageableProfilesResponse(result auth.ManageableProfiles) manageableProfilesResponse {
	response := manageableProfilesResponse{
		LoginID:     result.LoginID.String(),
		HouseholdID: result.HouseholdID.String(),
		Profiles:    make([]manageableProfileObject, 0, len(result.Profiles)),
	}

	for _, profile := range result.Profiles {
		response.Profiles = append(response.Profiles, manageableProfileObject{
			ID:          profile.ID.String(),
			DisplayName: profile.DisplayName,
			Role:        profile.Role,
		})
	}

	return response
}

type manageableProfilesServiceFunc func(context.Context, uuid.UUID) (auth.ManageableProfiles, error)

func (f manageableProfilesServiceFunc) ManageableProfiles(ctx context.Context, loginID uuid.UUID) (auth.ManageableProfiles, error) {
	return f(ctx, loginID)
}
