package auth

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
)

func TestServiceManageableProfilesReturnsResult(t *testing.T) {
	t.Parallel()

	loginID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
	expected := ManageableProfiles{
		LoginID:     loginID,
		HouseholdID: uuid.MustParse("00000000-0000-0000-0000-000000000010"),
		Profiles: []ManageableProfile{
			{
				ID:          uuid.MustParse("00000000-0000-0000-0000-000000000100"),
				DisplayName: "Alice Parent",
				Role:        "owner",
			},
		},
	}

	service := NewService(&fakeRepository{result: expected})

	got, err := service.ManageableProfiles(context.Background(), loginID)
	if err != nil {
		t.Fatalf("ManageableProfiles() error = %v", err)
	}

	if got.LoginID != expected.LoginID || got.HouseholdID != expected.HouseholdID || len(got.Profiles) != 1 {
		t.Fatalf("ManageableProfiles() = %+v, want %+v", got, expected)
	}
}

func TestServiceManageableProfilesPropagatesLoginNotFound(t *testing.T) {
	t.Parallel()

	service := NewService(&fakeRepository{err: ErrLoginNotFound})

	_, err := service.ManageableProfiles(context.Background(), uuid.New())
	if !errors.Is(err, ErrLoginNotFound) {
		t.Fatalf("ManageableProfiles() error = %v, want %v", err, ErrLoginNotFound)
	}
}

func TestServiceManageableProfilesPropagatesRepositoryError(t *testing.T) {
	t.Parallel()

	repositoryErr := errors.New("repository failed")
	service := NewService(&fakeRepository{err: repositoryErr})

	_, err := service.ManageableProfiles(context.Background(), uuid.New())
	if !errors.Is(err, repositoryErr) {
		t.Fatalf("ManageableProfiles() error = %v, want %v", err, repositoryErr)
	}
}

type fakeRepository struct {
	result ManageableProfiles
	err    error
}

func (r *fakeRepository) ManageableProfilesByLogin(context.Context, uuid.UUID) (ManageableProfiles, error) {
	if r.err != nil {
		return ManageableProfiles{}, r.err
	}

	return r.result, nil
}
