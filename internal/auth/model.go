// Package auth contains authorization query boundaries and service logic.
package auth

import "github.com/google/uuid"

// ManageableProfile is a profile the actor login may manage.
type ManageableProfile struct {
	ID          uuid.UUID
	DisplayName string
	Role        string
}

// ManageableProfiles is the household-scoped authorization result for a login.
type ManageableProfiles struct {
	LoginID     uuid.UUID
	HouseholdID uuid.UUID
	Profiles    []ManageableProfile
}
