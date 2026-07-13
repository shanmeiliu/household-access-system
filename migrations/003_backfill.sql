-- Backfill deterministic legacy records into the expanded household access model.
--
-- Production backfills normally run in bounded, observable batches with retry
-- and reconciliation metrics. This single transaction is acceptable for the
-- small deterministic local fixture.
--
-- This migration is additive. It does not change legacy columns, switch reads,
-- switch writes, or make the new model authoritative.

BEGIN;

CREATE TABLE IF NOT EXISTS migration_household_map (
    legacy_login_id UUID PRIMARY KEY,
    household_id UUID NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT migration_household_map_household_id_fkey
        FOREIGN KEY (household_id)
        REFERENCES households(id)
        ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS migration_exceptions (
    exception_key TEXT PRIMARY KEY,
    exception_code TEXT NOT NULL,
    legacy_login_id UUID NULL,
    profile_id UUID NULL,
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ NULL,
    CONSTRAINT migration_exceptions_profile_id_fkey
        FOREIGN KEY (profile_id)
        REFERENCES profiles(id)
        ON DELETE RESTRICT,
    CONSTRAINT migration_exceptions_status_check
        CHECK (status IN ('open', 'resolved', 'ignored')),
    CONSTRAINT migration_exceptions_lifecycle_check
        CHECK (
            (status = 'open' AND resolved_at IS NULL)
            OR (status IN ('resolved', 'ignored') AND resolved_at IS NOT NULL)
        )
);

CREATE INDEX IF NOT EXISTS idx_migration_exceptions_exception_code
    ON migration_exceptions(exception_code);

CREATE INDEX IF NOT EXISTS idx_migration_exceptions_status
    ON migration_exceptions(status);

CREATE INDEX IF NOT EXISTS idx_migration_exceptions_legacy_login_id
    ON migration_exceptions(legacy_login_id);

CREATE INDEX IF NOT EXISTS idx_migration_exceptions_profile_id
    ON migration_exceptions(profile_id);

CREATE TEMP TABLE tmp_legacy_group_analysis ON COMMIT DROP AS
WITH group_stats AS (
    SELECT
        p.login_id AS legacy_login_id,
        count(*) AS group_profile_count,
        count(*) FILTER (WHERE p.owner_name IS NOT NULL) AS non_null_owner_name_count,
        count(DISTINCT p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS distinct_owner_name_count,
        min(p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS owner_name,
        count(*) FILTER (WHERE p.login_email IS NOT NULL) AS login_email_count,
        array_agg(p.id ORDER BY p.display_name, p.id) AS profile_ids
    FROM profiles AS p
    WHERE p.login_id IS NOT NULL
    GROUP BY p.login_id
),
owner_matches AS (
    SELECT
        gs.legacy_login_id,
        count(po.id) AS matching_owner_profile_count,
        CASE
    WHEN count(po.id) = 1 THEN (array_agg(po.id ORDER BY po.id))[1]END AS owner_profile_id
    FROM group_stats AS gs
    LEFT JOIN profiles AS po
        ON po.display_name = gs.owner_name
    GROUP BY gs.legacy_login_id
),
owner_usage AS (
    SELECT
        owner_profile_id,
        count(*) AS owner_candidate_group_count
    FROM owner_matches
    WHERE owner_profile_id IS NOT NULL
    GROUP BY owner_profile_id
)
SELECT
    gs.legacy_login_id,
    gs.group_profile_count,
    gs.non_null_owner_name_count,
    gs.distinct_owner_name_count,
    gs.owner_name,
    gs.login_email_count,
    gs.profile_ids,
    om.matching_owner_profile_count,
    om.owner_profile_id,
    COALESCE(ou.owner_candidate_group_count, 0) AS owner_candidate_group_count,
    CASE
        WHEN gs.non_null_owner_name_count = 0 THEN 'MISSING_OWNER'
        WHEN gs.distinct_owner_name_count <> 1
            OR gs.non_null_owner_name_count <> gs.group_profile_count
            THEN 'INCONSISTENT_OWNER_NAME'
        WHEN om.matching_owner_profile_count = 0 THEN 'MISSING_OWNER'
        WHEN om.matching_owner_profile_count > 1 THEN 'AMBIGUOUS_OWNER'
        WHEN COALESCE(ou.owner_candidate_group_count, 0) > 1 THEN 'OWNER_IN_MULTIPLE_GROUPS'
        WHEN gs.login_email_count > 1 THEN 'MULTIPLE_LOGIN_EMAILS'
        ELSE NULL
    END AS base_exception_code
FROM group_stats AS gs
JOIN owner_matches AS om
    ON om.legacy_login_id = gs.legacy_login_id
LEFT JOIN owner_usage AS ou
    ON ou.owner_profile_id = om.owner_profile_id;

CREATE TEMP TABLE tmp_desired_membership_candidates ON COMMIT DROP AS
SELECT DISTINCT
    analysis.legacy_login_id,
    p.id AS profile_id,
    analysis.owner_profile_id,
    CASE
        WHEN p.id = analysis.owner_profile_id THEN 'owner'
        ELSE 'member'
    END AS role
FROM tmp_legacy_group_analysis AS analysis
JOIN profiles AS p
    ON p.login_id = analysis.legacy_login_id
    OR p.id = analysis.owner_profile_id
WHERE analysis.base_exception_code IS NULL;

CREATE TEMP TABLE tmp_overlapping_desired_profiles ON COMMIT DROP AS
SELECT
    profile_id,
    count(DISTINCT legacy_login_id) AS desired_group_count
FROM tmp_desired_membership_candidates
GROUP BY profile_id
HAVING count(DISTINCT legacy_login_id) > 1;

CREATE TEMP TABLE tmp_overlap_conflicts ON COMMIT DROP AS
SELECT
    desired.legacy_login_id,
    array_agg(DISTINCT desired.profile_id ORDER BY desired.profile_id) AS overlapping_profile_ids
FROM tmp_desired_membership_candidates AS desired
JOIN tmp_overlapping_desired_profiles AS overlap
    ON overlap.profile_id = desired.profile_id
GROUP BY desired.legacy_login_id;

CREATE TEMP TABLE tmp_existing_membership_conflicts ON COMMIT DROP AS
SELECT
    desired.legacy_login_id,
    array_agg(DISTINCT hm.profile_id ORDER BY hm.profile_id)
        FILTER (WHERE hm.profile_id IS NOT NULL) AS conflicting_profile_ids
FROM tmp_desired_membership_candidates AS desired
LEFT JOIN migration_household_map AS existing_map
    ON existing_map.legacy_login_id = desired.legacy_login_id
LEFT JOIN household_memberships AS hm
    ON hm.profile_id = desired.profile_id
   AND hm.status = 'active'
   AND (
       existing_map.household_id IS NULL
       OR hm.household_id <> existing_map.household_id
   )
GROUP BY desired.legacy_login_id
HAVING count(hm.id) > 0;

CREATE TEMP TABLE tmp_role_conflicts ON COMMIT DROP AS
SELECT
    desired.legacy_login_id,
    array_agg(DISTINCT desired.profile_id ORDER BY desired.profile_id) AS role_conflicting_profile_ids
FROM tmp_desired_membership_candidates AS desired
JOIN migration_household_map AS existing_map
    ON existing_map.legacy_login_id = desired.legacy_login_id
JOIN household_memberships AS hm
    ON hm.household_id = existing_map.household_id
   AND hm.profile_id = desired.profile_id
   AND hm.status = 'active'
   AND hm.role <> desired.role
GROUP BY desired.legacy_login_id;

CREATE TEMP TABLE tmp_mapping_contamination ON COMMIT DROP AS
WITH mapped_groups AS (
    SELECT
        analysis.legacy_login_id,
        existing_map.household_id AS mapped_household_id,
        h.status AS mapped_household_status
    FROM tmp_legacy_group_analysis AS analysis
    JOIN migration_household_map AS existing_map
        ON existing_map.legacy_login_id = analysis.legacy_login_id
    LEFT JOIN households AS h
        ON h.id = existing_map.household_id
    WHERE analysis.base_exception_code IS NULL
),
unexpected_destination_profiles AS (
    SELECT
        mapped.legacy_login_id,
        array_agg(DISTINCT hm.profile_id ORDER BY hm.profile_id) AS unexpected_destination_profile_ids
    FROM mapped_groups AS mapped
    JOIN household_memberships AS hm
        ON hm.household_id = mapped.mapped_household_id
       AND hm.status = 'active'
    LEFT JOIN tmp_desired_membership_candidates AS desired
        ON desired.legacy_login_id = mapped.legacy_login_id
       AND desired.profile_id = hm.profile_id
    WHERE desired.profile_id IS NULL
    GROUP BY mapped.legacy_login_id
),
desired_profiles_elsewhere AS (
    SELECT
        desired.legacy_login_id,
        array_agg(DISTINCT desired.profile_id ORDER BY desired.profile_id) AS conflicting_profile_ids
    FROM tmp_desired_membership_candidates AS desired
    JOIN mapped_groups AS mapped
        ON mapped.legacy_login_id = desired.legacy_login_id
    JOIN household_memberships AS hm
        ON hm.profile_id = desired.profile_id
       AND hm.status = 'active'
       AND hm.household_id <> mapped.mapped_household_id
    GROUP BY desired.legacy_login_id
)
SELECT
    mapped.legacy_login_id,
    mapped.mapped_household_id,
    mapped.mapped_household_status,
    desired_elsewhere.conflicting_profile_ids,
    unexpected.unexpected_destination_profile_ids
FROM mapped_groups AS mapped
LEFT JOIN desired_profiles_elsewhere AS desired_elsewhere
    ON desired_elsewhere.legacy_login_id = mapped.legacy_login_id
LEFT JOIN unexpected_destination_profiles AS unexpected
    ON unexpected.legacy_login_id = mapped.legacy_login_id
WHERE mapped.mapped_household_status IS DISTINCT FROM 'active'
   OR desired_elsewhere.conflicting_profile_ids IS NOT NULL
   OR unexpected.unexpected_destination_profile_ids IS NOT NULL;

CREATE TEMP TABLE tmp_ambiguous_legacy_groups ON COMMIT DROP AS
SELECT
    analysis.legacy_login_id,
    CASE
        WHEN analysis.base_exception_code IS NOT NULL THEN analysis.base_exception_code
        WHEN overlap.legacy_login_id IS NOT NULL THEN 'MEMBERSHIP_CONFLICT'
        WHEN existing_conflicts.legacy_login_id IS NOT NULL THEN 'MEMBERSHIP_CONFLICT'
        WHEN role_conflicts.legacy_login_id IS NOT NULL THEN 'MEMBERSHIP_CONFLICT'
        WHEN contamination.legacy_login_id IS NOT NULL THEN 'MEMBERSHIP_CONFLICT'
    END AS exception_code,
    analysis.owner_name,
    analysis.matching_owner_profile_count,
    analysis.group_profile_count,
    analysis.login_email_count,
    analysis.profile_ids,
    overlap.overlapping_profile_ids,
    existing_conflicts.conflicting_profile_ids AS existing_conflicting_profile_ids,
    role_conflicts.role_conflicting_profile_ids,
    contamination.conflicting_profile_ids AS contamination_conflicting_profile_ids,
    contamination.unexpected_destination_profile_ids,
    contamination.mapped_household_id,
    contamination.mapped_household_status
FROM tmp_legacy_group_analysis AS analysis
LEFT JOIN tmp_overlap_conflicts AS overlap
    ON overlap.legacy_login_id = analysis.legacy_login_id
LEFT JOIN tmp_existing_membership_conflicts AS existing_conflicts
    ON existing_conflicts.legacy_login_id = analysis.legacy_login_id
LEFT JOIN tmp_role_conflicts AS role_conflicts
    ON role_conflicts.legacy_login_id = analysis.legacy_login_id
LEFT JOIN tmp_mapping_contamination AS contamination
    ON contamination.legacy_login_id = analysis.legacy_login_id
WHERE analysis.base_exception_code IS NOT NULL
   OR overlap.legacy_login_id IS NOT NULL
   OR existing_conflicts.legacy_login_id IS NOT NULL
   OR role_conflicts.legacy_login_id IS NOT NULL
   OR contamination.legacy_login_id IS NOT NULL;

CREATE TEMP TABLE tmp_eligible_legacy_groups ON COMMIT DROP AS
SELECT
    analysis.legacy_login_id,
    analysis.owner_name,
    analysis.owner_profile_id
FROM tmp_legacy_group_analysis AS analysis
LEFT JOIN tmp_ambiguous_legacy_groups AS ambiguous
    ON ambiguous.legacy_login_id = analysis.legacy_login_id
WHERE analysis.base_exception_code IS NULL
  AND ambiguous.legacy_login_id IS NULL;

INSERT INTO migration_exceptions (
    exception_key,
    exception_code,
    legacy_login_id,
    details
)
SELECT
    'legacy-group:' || ambiguous.legacy_login_id || ':' ||
        CASE ambiguous.exception_code
            WHEN 'AMBIGUOUS_OWNER' THEN 'ambiguous-owner'
            WHEN 'MISSING_OWNER' THEN 'missing-owner'
            WHEN 'INCONSISTENT_OWNER_NAME' THEN 'inconsistent-owner-name'
            WHEN 'MULTIPLE_LOGIN_EMAILS' THEN 'multiple-login-emails'
            WHEN 'OWNER_IN_MULTIPLE_GROUPS' THEN 'owner-used-by-multiple-groups'
            WHEN 'MEMBERSHIP_CONFLICT' THEN 'membership-conflict'
            ELSE lower(ambiguous.exception_code)
        END AS exception_key,
    ambiguous.exception_code,
    ambiguous.legacy_login_id,
    jsonb_build_object(
        'owner_name', ambiguous.owner_name,
        'matching_owner_profile_count', ambiguous.matching_owner_profile_count,
        'group_profile_count', ambiguous.group_profile_count,
        'login_email_count', ambiguous.login_email_count,
        'profile_ids', to_jsonb(ambiguous.profile_ids),
        'overlapping_profile_ids', to_jsonb(ambiguous.overlapping_profile_ids),
        'role_conflicting_profile_ids', to_jsonb(ambiguous.role_conflicting_profile_ids),
        'conflicting_profile_ids', to_jsonb(
            ARRAY(
                SELECT DISTINCT conflict_profile_id
                FROM unnest(
                    COALESCE(ambiguous.existing_conflicting_profile_ids, ARRAY[]::uuid[])
                    || COALESCE(ambiguous.contamination_conflicting_profile_ids, ARRAY[]::uuid[])
                ) AS conflict(conflict_profile_id)
                ORDER BY conflict_profile_id
            )
        ),
        'unexpected_destination_profile_ids', to_jsonb(ambiguous.unexpected_destination_profile_ids),
        'mapped_household_id', ambiguous.mapped_household_id,
        'mapped_household_status', ambiguous.mapped_household_status
    ) AS details
FROM tmp_ambiguous_legacy_groups AS ambiguous
ON CONFLICT (exception_key) DO UPDATE
SET
    exception_code = EXCLUDED.exception_code,
    legacy_login_id = EXCLUDED.legacy_login_id,
    details = EXCLUDED.details
WHERE migration_exceptions.status = 'open';

INSERT INTO migration_exceptions (
    exception_key,
    exception_code,
    profile_id,
    details
)
SELECT
    'profile:' || p.id || ':unassigned' AS exception_key,
    'UNASSIGNED_NULL_LOGIN_PROFILE' AS exception_code,
    p.id AS profile_id,
    jsonb_build_object(
        'display_name', p.display_name,
        'reason', 'profile has null login_id and no deterministic eligible household assignment'
    ) AS details
FROM profiles AS p
WHERE p.login_id IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM tmp_eligible_legacy_groups AS eligible
      WHERE eligible.owner_profile_id = p.id
  )
ON CONFLICT (exception_key) DO UPDATE
SET
    exception_code = EXCLUDED.exception_code,
    profile_id = EXCLUDED.profile_id,
    details = EXCLUDED.details
WHERE migration_exceptions.status = 'open';

CREATE TEMP TABLE tmp_desired_household_mappings ON COMMIT DROP AS
SELECT
    eligible.legacy_login_id,
    COALESCE(existing_map.household_id, gen_random_uuid()) AS household_id
FROM tmp_eligible_legacy_groups AS eligible
LEFT JOIN migration_household_map AS existing_map
    ON existing_map.legacy_login_id = eligible.legacy_login_id;

INSERT INTO households (
    id,
    status
)
SELECT
    desired.household_id,
    'active'
FROM tmp_desired_household_mappings AS desired
ON CONFLICT (id) DO NOTHING;

INSERT INTO migration_household_map (
    legacy_login_id,
    household_id
)
SELECT
    desired.legacy_login_id,
    desired.household_id
FROM tmp_desired_household_mappings AS desired
ON CONFLICT (legacy_login_id) DO NOTHING;

CREATE TEMP TABLE tmp_eligible_membership_profiles ON COMMIT DROP AS
SELECT
    desired.household_id,
    membership.profile_id,
    membership.role
FROM tmp_desired_membership_candidates AS membership
JOIN tmp_desired_household_mappings AS desired
    ON desired.legacy_login_id = membership.legacy_login_id
JOIN tmp_eligible_legacy_groups AS eligible
    ON eligible.legacy_login_id = membership.legacy_login_id;

INSERT INTO household_memberships (
    household_id,
    profile_id,
    role,
    status
)
SELECT
    membership.household_id,
    membership.profile_id,
    membership.role,
    'active'
FROM tmp_eligible_membership_profiles AS membership
WHERE NOT EXISTS (
    SELECT 1
    FROM household_memberships AS existing_membership
    WHERE existing_membership.profile_id = membership.profile_id
      AND existing_membership.status = 'active'
);

CREATE TEMP TABLE tmp_deterministic_login_profiles ON COMMIT DROP AS
SELECT DISTINCT
    p.id AS profile_id,
    p.login_email
FROM tmp_desired_membership_candidates AS desired
JOIN tmp_eligible_legacy_groups AS eligible
    ON eligible.legacy_login_id = desired.legacy_login_id
JOIN profiles AS p
    ON p.id = desired.profile_id
WHERE p.login_email IS NOT NULL;

INSERT INTO migration_exceptions (
    exception_key,
    exception_code,
    profile_id,
    details
)
SELECT
    'profile:' || login_profile.profile_id || ':login-account-conflict' AS exception_key,
    'LOGIN_ACCOUNT_CONFLICT' AS exception_code,
    login_profile.profile_id,
    jsonb_build_object(
        'expected_email', login_profile.login_email,
        'existing_email', existing_login.email,
        'existing_status', existing_login.status,
        'existing_identity_provider', existing_login.identity_provider,
        'existing_external_subject', existing_login.external_subject
    ) AS details
FROM tmp_deterministic_login_profiles AS login_profile
JOIN login_accounts AS existing_login
    ON existing_login.profile_id = login_profile.profile_id
WHERE existing_login.email IS DISTINCT FROM login_profile.login_email
   OR existing_login.status <> 'active'
   OR existing_login.identity_provider IS NOT NULL
   OR existing_login.external_subject IS NOT NULL
ON CONFLICT (exception_key) DO UPDATE
SET
    exception_code = EXCLUDED.exception_code,
    profile_id = EXCLUDED.profile_id,
    details = EXCLUDED.details
WHERE migration_exceptions.status = 'open';

INSERT INTO login_accounts (
    profile_id,
    email,
    identity_provider,
    external_subject,
    status
)
SELECT
    login_profile.profile_id,
    login_profile.login_email,
    NULL,
    NULL,
    'active'
FROM tmp_deterministic_login_profiles AS login_profile
WHERE NOT EXISTS (
    SELECT 1
    FROM login_accounts AS existing_login
    WHERE existing_login.profile_id = login_profile.profile_id
);

COMMIT;

-- Expected fixture result after 001_legacy_schema.sql, 002_new_schema.sql, and
-- this deterministic backfill:
--
-- 3 households
-- 8 active memberships
-- 3 login accounts
-- 2 open migration exceptions
--
-- The ambiguous Jordan Lee group and Dana Staff Created profile remain outside
-- new-model authorization until explicit review resolves their exceptions.
