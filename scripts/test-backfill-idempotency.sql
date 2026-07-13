\echo 'Backfill idempotency snapshot counts'
SELECT 'households' AS metric, count(*) AS value
FROM households
UNION ALL
SELECT 'distinct_mapped_households' AS metric, count(DISTINCT household_id) AS value
FROM migration_household_map
UNION ALL
SELECT 'migration_household_map' AS metric, count(*) AS value
FROM migration_household_map
UNION ALL
SELECT 'active_memberships' AS metric, count(*) AS value
FROM household_memberships
WHERE status = 'active'
UNION ALL
SELECT 'login_accounts' AS metric, count(*) AS value
FROM login_accounts
UNION ALL
SELECT 'open_migration_exceptions' AS metric, count(*) AS value
FROM migration_exceptions
WHERE status = 'open'
ORDER BY metric;

\echo 'Duplicate active memberships by profile; expected zero rows'
SELECT profile_id, count(*) AS active_membership_count
FROM household_memberships
WHERE status = 'active'
GROUP BY profile_id
HAVING count(*) > 1
ORDER BY profile_id;

\echo 'Duplicate login rows by profile; expected zero rows'
SELECT profile_id, count(*) AS login_account_count
FROM login_accounts
GROUP BY profile_id
HAVING count(*) > 1
ORDER BY profile_id;

\echo 'Duplicate mappings by legacy login ID; expected zero rows'
SELECT legacy_login_id, count(*) AS mapping_count
FROM migration_household_map
GROUP BY legacy_login_id
HAVING count(*) > 1
ORDER BY legacy_login_id;

\echo 'Households with zero or multiple active owners; expected zero rows'
SELECT
    h.id AS household_id,
    count(hm.id) AS active_owner_count
FROM households AS h
LEFT JOIN household_memberships AS hm
    ON hm.household_id = h.id
   AND hm.role = 'owner'
   AND hm.status = 'active'
WHERE h.status = 'active'
GROUP BY h.id
HAVING count(hm.id) <> 1
ORDER BY h.id;

\echo 'Profiles active in multiple migration households; expected zero rows'
SELECT
    hm.profile_id,
    count(DISTINCT mhm.household_id) AS mapped_household_count
FROM household_memberships AS hm
JOIN migration_household_map AS mhm
    ON mhm.household_id = hm.household_id
WHERE hm.status = 'active'
GROUP BY hm.profile_id
HAVING count(DISTINCT mhm.household_id) > 1
ORDER BY hm.profile_id;

\echo 'Mapped households containing profiles outside their deterministic group; expected zero rows'
WITH group_stats AS (
    SELECT
        p.login_id AS legacy_login_id,
        count(*) AS group_profile_count,
        count(*) FILTER (WHERE p.owner_name IS NOT NULL) AS non_null_owner_name_count,
        count(DISTINCT p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS distinct_owner_name_count,
        min(p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS owner_name
    FROM profiles AS p
    WHERE p.login_id IS NOT NULL
    GROUP BY p.login_id
),
owner_matches AS (
    SELECT
        gs.legacy_login_id,
        CASE
    WHEN count(po.id) = 1 THEN (array_agg(po.id ORDER BY po.id))[1]END AS owner_profile_id
    FROM group_stats AS gs
    LEFT JOIN profiles AS po
        ON po.display_name = gs.owner_name
    WHERE gs.non_null_owner_name_count > 0
        AND gs.non_null_owner_name_count = gs.group_profile_count
        AND gs.distinct_owner_name_count = 1
    GROUP BY gs.legacy_login_id
),
expected_memberships AS (
    SELECT
        mhm.legacy_login_id,
        mhm.household_id,
        p.id AS profile_id
    FROM migration_household_map AS mhm
    JOIN owner_matches AS owner_match
        ON owner_match.legacy_login_id = mhm.legacy_login_id
    JOIN profiles AS p
        ON p.login_id = mhm.legacy_login_id
        OR p.id = owner_match.owner_profile_id
)
SELECT
    mhm.legacy_login_id,
    mhm.household_id,
    hm.profile_id
FROM migration_household_map AS mhm
JOIN household_memberships AS hm
    ON hm.household_id = mhm.household_id
   AND hm.status = 'active'
LEFT JOIN expected_memberships AS expected
    ON expected.legacy_login_id = mhm.legacy_login_id
   AND expected.household_id = hm.household_id
   AND expected.profile_id = hm.profile_id
WHERE expected.profile_id IS NULL
ORDER BY mhm.legacy_login_id, hm.profile_id;

\echo 'Mapped household memberships with unexpected roles; expected zero rows'
WITH group_stats AS (
    SELECT
        p.login_id AS legacy_login_id,
        count(*) FILTER (WHERE p.owner_name IS NOT NULL) AS non_null_owner_name_count,
        count(DISTINCT p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS distinct_owner_name_count,
        min(p.owner_name) FILTER (WHERE p.owner_name IS NOT NULL) AS owner_name
    FROM profiles AS p
    WHERE p.login_id IS NOT NULL
    GROUP BY p.login_id
),
owner_matches AS (
    SELECT
        gs.legacy_login_id,
        CASE
    WHEN count(po.id) = 1 THEN (array_agg(po.id ORDER BY po.id))[1]END AS owner_profile_id
    FROM group_stats AS gs
    LEFT JOIN profiles AS po
        ON po.display_name = gs.owner_name
    WHERE gs.non_null_owner_name_count > 0
      AND gs.distinct_owner_name_count = 1
    GROUP BY gs.legacy_login_id
),
expected_memberships AS (
    SELECT
        mhm.legacy_login_id,
        mhm.household_id,
        p.id AS profile_id,
        CASE
            WHEN p.id = owner_match.owner_profile_id THEN 'owner'
            ELSE 'member'
        END AS expected_role
    FROM migration_household_map AS mhm
    JOIN owner_matches AS owner_match
        ON owner_match.legacy_login_id = mhm.legacy_login_id
    JOIN profiles AS p
        ON p.login_id = mhm.legacy_login_id
        OR p.id = owner_match.owner_profile_id
)
SELECT
    expected.legacy_login_id,
    expected.household_id,
    expected.profile_id,
    expected.expected_role,
    hm.role AS actual_role
FROM expected_memberships AS expected
JOIN household_memberships AS hm
    ON hm.household_id = expected.household_id
   AND hm.profile_id = expected.profile_id
   AND hm.status = 'active'
WHERE hm.role <> expected.expected_role
ORDER BY expected.legacy_login_id, expected.profile_id;
