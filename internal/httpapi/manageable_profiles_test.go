package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/shanmeiliu/household-access-system/internal/auth"
)

func TestManageableProfilesReturnsProfiles(t *testing.T) {
	t.Parallel()

	loginID := uuid.MustParse("00000000-0000-0000-0000-000000000001")
	householdID := uuid.MustParse("00000000-0000-0000-0000-000000000010")
	server := &Server{
		logger: slog.Default(),
		auth: manageableProfilesServiceFunc(func(_ context.Context, gotLoginID uuid.UUID) (auth.ManageableProfiles, error) {
			if gotLoginID != loginID {
				t.Fatalf("loginID = %s, want %s", gotLoginID, loginID)
			}

			return auth.ManageableProfiles{
				LoginID:     loginID,
				HouseholdID: householdID,
				Profiles: []auth.ManageableProfile{
					{
						ID:          uuid.MustParse("00000000-0000-0000-0000-000000000100"),
						DisplayName: "Alice Parent",
						Role:        "owner",
					},
					{
						ID:          uuid.MustParse("00000000-0000-0000-0000-000000000101"),
						DisplayName: "Bob Parent",
						Role:        "member",
					},
				},
			}, nil
		}),
	}

	response := executeManageableProfilesRequest(server, loginID.String())

	if response.Code != http.StatusOK {
		t.Fatalf("status code = %d, want %d", response.Code, http.StatusOK)
	}

	var body manageableProfilesResponse
	decodeResponse(t, response, &body)

	if body.LoginID != loginID.String() {
		t.Fatalf("login_id = %q, want %q", body.LoginID, loginID.String())
	}
	if body.HouseholdID != householdID.String() {
		t.Fatalf("household_id = %q, want %q", body.HouseholdID, householdID.String())
	}
	if len(body.Profiles) != 2 {
		t.Fatalf("profiles length = %d, want %d", len(body.Profiles), 2)
	}
	if body.Profiles[0].Role != "owner" || body.Profiles[0].DisplayName != "Alice Parent" {
		t.Fatalf("first profile = %+v, want owner Alice Parent", body.Profiles[0])
	}
	if body.Profiles[1].Role != "member" || body.Profiles[1].DisplayName != "Bob Parent" {
		t.Fatalf("second profile = %+v, want member Bob Parent", body.Profiles[1])
	}
}

func TestManageableProfilesInvalidUUID(t *testing.T) {
	t.Parallel()

	server := &Server{logger: slog.Default()}
	response := executeManageableProfilesRequest(server, "not-a-uuid")

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status code = %d, want %d", response.Code, http.StatusBadRequest)
	}

	var body errorResponse
	decodeResponse(t, response, &body)

	if body.Error != "invalid_login_id" {
		t.Fatalf("error = %q, want %q", body.Error, "invalid_login_id")
	}
}

func TestManageableProfilesLoginNotFound(t *testing.T) {
	t.Parallel()

	server := &Server{
		logger: slog.Default(),
		auth: manageableProfilesServiceFunc(func(context.Context, uuid.UUID) (auth.ManageableProfiles, error) {
			return auth.ManageableProfiles{}, auth.ErrLoginNotFound
		}),
	}

	response := executeManageableProfilesRequest(server, uuid.NewString())

	if response.Code != http.StatusNotFound {
		t.Fatalf("status code = %d, want %d", response.Code, http.StatusNotFound)
	}

	var body errorResponse
	decodeResponse(t, response, &body)

	if body.Error != "login_not_found" {
		t.Fatalf("error = %q, want %q", body.Error, "login_not_found")
	}
}

func TestManageableProfilesInternalError(t *testing.T) {
	t.Parallel()

	server := &Server{
		logger: slog.Default(),
		auth: manageableProfilesServiceFunc(func(context.Context, uuid.UUID) (auth.ManageableProfiles, error) {
			return auth.ManageableProfiles{}, errors.New("repository failed")
		}),
	}

	response := executeManageableProfilesRequest(server, uuid.NewString())

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status code = %d, want %d", response.Code, http.StatusInternalServerError)
	}

	var body errorResponse
	decodeResponse(t, response, &body)

	if body.Error != "internal_error" {
		t.Fatalf("error = %q, want %q", body.Error, "internal_error")
	}
}

func TestManageableProfilesPreservesServiceOrder(t *testing.T) {
	t.Parallel()

	server := &Server{
		logger: slog.Default(),
		auth: manageableProfilesServiceFunc(func(context.Context, uuid.UUID) (auth.ManageableProfiles, error) {
			return auth.ManageableProfiles{
				LoginID:     uuid.MustParse("00000000-0000-0000-0000-000000000001"),
				HouseholdID: uuid.MustParse("00000000-0000-0000-0000-000000000010"),
				Profiles: []auth.ManageableProfile{
					{ID: uuid.MustParse("00000000-0000-0000-0000-000000000100"), DisplayName: "Owner", Role: "owner"},
					{ID: uuid.MustParse("00000000-0000-0000-0000-000000000101"), DisplayName: "Alpha", Role: "member"},
					{ID: uuid.MustParse("00000000-0000-0000-0000-000000000102"), DisplayName: "Beta", Role: "member"},
				},
			}, nil
		}),
	}

	response := executeManageableProfilesRequest(server, uuid.NewString())

	var body manageableProfilesResponse
	decodeResponse(t, response, &body)

	gotNames := []string{body.Profiles[0].DisplayName, body.Profiles[1].DisplayName, body.Profiles[2].DisplayName}
	wantNames := []string{"Owner", "Alpha", "Beta"}
	for i := range wantNames {
		if gotNames[i] != wantNames[i] {
			t.Fatalf("profile order = %v, want %v", gotNames, wantNames)
		}
	}
}

func executeManageableProfilesRequest(server *Server, loginID string) *httptest.ResponseRecorder {
	request := httptest.NewRequest(http.MethodGet, "/logins/"+loginID+"/manageable-profiles", nil)
	request.SetPathValue("loginID", loginID)
	response := httptest.NewRecorder()

	server.handleManageableProfiles(response, request)

	return response
}

func decodeResponse[T any](t *testing.T, response *httptest.ResponseRecorder, target *T) {
	t.Helper()

	if err := json.NewDecoder(response.Body).Decode(target); err != nil {
		t.Fatalf("decode response body: %v", err)
	}
}
