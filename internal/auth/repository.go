package auth

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrLoginNotFound is returned when a login cannot authorize any active household.
var ErrLoginNotFound = errors.New("login not found")

// Repository loads authorization views for login accounts.
type Repository interface {
	ManageableProfilesByLogin(ctx context.Context, loginID uuid.UUID) (ManageableProfiles, error)
}

// PostgresRepository is a PostgreSQL-backed auth repository.
type PostgresRepository struct {
	pool *pgxpool.Pool
}

// NewPostgresRepository creates a PostgreSQL-backed auth repository.
func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

// ManageableProfilesByLogin returns every active profile the active login may manage.
func (r *PostgresRepository) ManageableProfilesByLogin(ctx context.Context, loginID uuid.UUID) (ManageableProfiles, error) {
	const query = `
SELECT
    household.id AS household_id,
    target_profile.id AS profile_id,
    target_profile.display_name,
    target_membership.role
FROM login_accounts AS actor_login
JOIN profiles AS actor_profile
  ON actor_profile.id = actor_login.profile_id
JOIN household_memberships AS actor_membership
  ON actor_membership.profile_id = actor_profile.id
JOIN households AS household
  ON household.id = actor_membership.household_id
JOIN household_memberships AS target_membership
  ON target_membership.household_id = household.id
JOIN profiles AS target_profile
  ON target_profile.id = target_membership.profile_id
WHERE actor_login.id = $1
  AND actor_login.status = 'active'
  AND actor_profile.status = 'active'
  AND actor_membership.status = 'active'
  AND household.status = 'active'
  AND target_membership.status = 'active'
  AND target_profile.status = 'active'
ORDER BY
    CASE WHEN target_membership.role = 'owner' THEN 0 ELSE 1 END,
    target_profile.display_name,
    target_profile.id`

	rows, err := r.pool.Query(ctx, query, loginID)
	if err != nil {
		return ManageableProfiles{}, fmt.Errorf("query manageable profiles: %w", err)
	}
	defer rows.Close()

	result := ManageableProfiles{
		LoginID:  loginID,
		Profiles: make([]ManageableProfile, 0),
	}

	for rows.Next() {
		var householdID uuid.UUID
		var profile ManageableProfile

		if err := rows.Scan(&householdID, &profile.ID, &profile.DisplayName, &profile.Role); err != nil {
			return ManageableProfiles{}, fmt.Errorf("scan manageable profile: %w", err)
		}

		if result.HouseholdID == uuid.Nil {
			result.HouseholdID = householdID
		} else if result.HouseholdID != householdID {
			return ManageableProfiles{}, fmt.Errorf("inconsistent household scope for login %s", loginID)
		}

		result.Profiles = append(result.Profiles, profile)
	}

	if err := rows.Err(); err != nil {
		return ManageableProfiles{}, fmt.Errorf("iterate manageable profiles: %w", err)
	}

	if len(result.Profiles) == 0 {
		return ManageableProfiles{}, ErrLoginNotFound
	}

	return result, nil
}
