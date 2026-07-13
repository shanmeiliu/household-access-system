\echo 'Backfill counts'
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

\echo 'Household mapping'
SELECT legacy_login_id, household_id
FROM migration_household_map
ORDER BY legacy_login_id;

\echo 'Membership results'
SELECT
    hm.household_id,
    p.display_name,
    hm.role,
    hm.status AS membership_status
FROM household_memberships AS hm
JOIN profiles AS p
    ON p.id = hm.profile_id
ORDER BY hm.household_id, hm.role DESC, p.display_name;

\echo 'Login account results'
SELECT
    p.display_name,
    la.email,
    la.status
FROM login_accounts AS la
JOIN profiles AS p
    ON p.id = la.profile_id
ORDER BY p.display_name;

\echo 'Migration exceptions'
SELECT
    me.exception_key,
    me.exception_code,
    me.legacy_login_id,
    p.display_name,
    me.details,
    me.status
FROM migration_exceptions AS me
LEFT JOIN profiles AS p
    ON p.id = me.profile_id
ORDER BY me.exception_key;

\echo 'Expected deterministic checks'
SELECT
    'exactly 3 migration household mappings' AS check_name,
    count(*) = 3 AS passed,
    count(*) AS actual
FROM migration_household_map;

SELECT
    'exactly 3 distinct mapped households' AS check_name,
    count(*) = 3 AS passed,
    count(*) AS actual
FROM (
    SELECT DISTINCT household_id
    FROM migration_household_map
) AS mapped_households;

SELECT
    'exactly 8 active memberships' AS check_name,
    count(*) = 8 AS passed,
    count(*) AS actual
FROM household_memberships
WHERE status = 'active';

SELECT
    'exactly 3 login accounts' AS check_name,
    count(*) = 3 AS passed,
    count(*) AS actual
FROM login_accounts;

SELECT
    'exactly 2 open exceptions' AS check_name,
    count(*) = 2 AS passed,
    count(*) AS actual
FROM migration_exceptions
WHERE status = 'open';

SELECT
    'Dana Staff Created has no active membership' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM profiles AS p
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE p.display_name = 'Dana Staff Created'
          AND hm.status = 'active'
    ) AS passed;

SELECT
    'No profile named Jordan Lee has an active membership' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM profiles AS p
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE p.display_name = 'Jordan Lee'
          AND hm.status = 'active'
    ) AS passed;

SELECT
    'Evelyn Owner has an active owner membership' AS check_name,
    EXISTS (
        SELECT 1
        FROM profiles AS p
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE p.display_name = 'Evelyn Owner'
          AND hm.role = 'owner'
          AND hm.status = 'active'
    ) AS passed;

SELECT
    'ambiguous Jordan login group has no mapping' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM migration_household_map
        WHERE legacy_login_id = '44444444-4444-4444-4444-444444444444'
    ) AS passed;

SELECT
    'every backfilled active household has exactly one active owner' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM migration_household_map AS mhm
        JOIN households AS h
            ON h.id = mhm.household_id
        LEFT JOIN household_memberships AS hm
            ON hm.household_id = h.id
           AND hm.role = 'owner'
           AND hm.status = 'active'
        WHERE h.status = 'active'
        GROUP BY h.id
        HAVING count(hm.id) <> 1
    ) AS passed;
