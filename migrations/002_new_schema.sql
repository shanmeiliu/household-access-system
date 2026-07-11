-- Expand-phase migration for the new household access model.
--
-- This migration adds the new model alongside the legacy profiles schema. It
-- does not backfill existing profiles, switch reads, switch writes, or change
-- current authorization behavior. The application can continue using legacy
-- profiles.login_id, profiles.login_email, and profiles.owner_name during
-- migration and rollback.
--
-- IF NOT EXISTS supports local fixture reruns. It is not a substitute for a
-- formal production migration ledger.

BEGIN;

CREATE TABLE IF NOT EXISTS login_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID NOT NULL,
    email TEXT NULL,
    identity_provider TEXT NULL,
    external_subject TEXT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    disabled_at TIMESTAMPTZ NULL,
    deleted_at TIMESTAMPTZ NULL,
    CONSTRAINT login_accounts_profile_id_fkey
        FOREIGN KEY (profile_id)
        REFERENCES profiles(id)
        ON DELETE RESTRICT,
    CONSTRAINT login_accounts_profile_id_key UNIQUE (profile_id),
    CONSTRAINT login_accounts_status_check
        CHECK (status IN ('active', 'disabled', 'deleted')),
    CONSTRAINT login_accounts_lifecycle_check
        CHECK (
            (status = 'active' AND disabled_at IS NULL AND deleted_at IS NULL)
            OR (status = 'disabled' AND disabled_at IS NOT NULL AND deleted_at IS NULL)
            OR (status = 'deleted' AND deleted_at IS NOT NULL)
        ),
    CONSTRAINT login_accounts_identity_pair_check
        CHECK (
            (identity_provider IS NULL AND external_subject IS NULL)
            OR (identity_provider IS NOT NULL AND external_subject IS NOT NULL)
        )
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_login_accounts_external_identity_non_deleted
    ON login_accounts(identity_provider, external_subject)
    WHERE identity_provider IS NOT NULL
      AND external_subject IS NOT NULL
      AND status <> 'deleted';

CREATE INDEX IF NOT EXISTS idx_login_accounts_status
    ON login_accounts(status);

CREATE INDEX IF NOT EXISTS idx_login_accounts_lower_email
    ON login_accounts(lower(email))
    WHERE email IS NOT NULL;

CREATE TABLE IF NOT EXISTS households (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    archived_at TIMESTAMPTZ NULL,
    CONSTRAINT households_status_check
        CHECK (status IN ('active', 'archived')),
    CONSTRAINT households_lifecycle_check
        CHECK (
            (status = 'active' AND archived_at IS NULL)
            OR (status = 'archived' AND archived_at IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_households_status
    ON households(status);

CREATE TABLE IF NOT EXISTS household_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL,
    profile_id UUID NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    removed_at TIMESTAMPTZ NULL,
    CONSTRAINT household_memberships_household_id_fkey
        FOREIGN KEY (household_id)
        REFERENCES households(id)
        ON DELETE RESTRICT,
    CONSTRAINT household_memberships_profile_id_fkey
        FOREIGN KEY (profile_id)
        REFERENCES profiles(id)
        ON DELETE RESTRICT,
    CONSTRAINT household_memberships_role_check
        CHECK (role IN ('owner', 'member')),
    CONSTRAINT household_memberships_status_check
        CHECK (status IN ('active', 'removed')),
    CONSTRAINT household_memberships_lifecycle_check
        CHECK (
            (status = 'active' AND removed_at IS NULL)
            OR (status = 'removed' AND removed_at IS NOT NULL)
        )
);

-- A profile can have many historical membership rows, but only one active
-- membership at a time.
CREATE UNIQUE INDEX IF NOT EXISTS uq_household_memberships_active_profile
    ON household_memberships(profile_id)
    WHERE status = 'active';

-- This prevents multiple active owners in one household. It does not prevent an
-- active household from temporarily having zero owners. Exactly-one-owner
-- enforcement will be added only after backfill and validation in
-- 004_constraints.sql. Creation and ownership-transfer workflows will later use
-- transactions to preserve the invariant at service boundaries.
CREATE UNIQUE INDEX IF NOT EXISTS uq_household_memberships_active_owner
    ON household_memberships(household_id)
    WHERE role = 'owner'
      AND status = 'active';

CREATE INDEX IF NOT EXISTS idx_household_memberships_active_household
    ON household_memberships(household_id)
    WHERE status = 'active';

CREATE INDEX IF NOT EXISTS idx_household_memberships_household_id
    ON household_memberships(household_id);

CREATE INDEX IF NOT EXISTS idx_household_memberships_profile_id
    ON household_memberships(profile_id);

CREATE INDEX IF NOT EXISTS idx_household_memberships_status
    ON household_memberships(status);

COMMIT;
