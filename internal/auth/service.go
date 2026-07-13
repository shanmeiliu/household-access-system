package auth

import (
	"context"

	"github.com/google/uuid"
)

// Service coordinates authorization use cases.
type Service struct {
	repository Repository
}

// NewService creates an auth service.
func NewService(repository Repository) *Service {
	return &Service{repository: repository}
}

// ManageableProfiles returns every profile the login may manage.
func (s *Service) ManageableProfiles(ctx context.Context, loginID uuid.UUID) (ManageableProfiles, error) {
	return s.repository.ManageableProfilesByLogin(ctx, loginID)
}
