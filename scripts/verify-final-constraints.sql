\echo 'Final validation functions'
SELECT
    n.nspname AS schema_name,
    p.proname AS function_name
FROM pg_proc AS p
JOIN pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'assert_household_exactly_one_active_owner',
      'assert_profile_has_no_active_membership_when_archived',
      'check_household_owner_after_membership_change',
      'check_household_owner_after_household_change',
      'check_profile_membership_after_profile_change'
  )
ORDER BY p.proname;

\echo 'Deferred constraint triggers'
SELECT
    tgname AS trigger_name,
    tgconstraint <> 0 AS is_constraint_trigger,
    tgdeferrable AS is_deferrable,
    tginitdeferred AS is_initially_deferred,
    NOT tgisinternal AS is_user_trigger,
    tgenabled AS enabled_state
FROM pg_trigger
WHERE tgname IN (
    'household_memberships_exactly_one_owner_trigger',
    'households_exactly_one_owner_trigger',
    'profiles_no_active_membership_when_archived_trigger'
)
  AND NOT tgisinternal
ORDER BY tgname;

\echo 'Active-owner partial unique index'
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname = 'uq_household_memberships_active_owner';

\echo 'Active household owner counts'
SELECT
    h.id AS household_id,
    count(hm.id) AS active_owner_count
FROM households AS h
LEFT JOIN household_memberships AS hm
    ON hm.household_id = h.id
   AND hm.status = 'active'
   AND hm.role = 'owner'
WHERE h.status = 'active'
GROUP BY h.id
ORDER BY h.id;

\echo 'Archived households with active memberships; expected zero rows'
SELECT
    h.id AS household_id,
    hm.id AS membership_id,
    hm.profile_id
FROM households AS h
JOIN household_memberships AS hm
    ON hm.household_id = h.id
WHERE h.status = 'archived'
  AND hm.status = 'active'
ORDER BY h.id, hm.id;

\echo 'Archived profiles with active memberships; expected zero rows'
SELECT
    hm.household_id,
    hm.id AS membership_id,
    p.id AS profile_id,
    p.display_name
FROM household_memberships AS hm
JOIN profiles AS p
    ON p.id = hm.profile_id
WHERE hm.status = 'active'
  AND p.status = 'archived'
ORDER BY hm.household_id, p.display_name;

\echo 'Migration exceptions'
SELECT
    exception_key,
    exception_code,
    legacy_login_id,
    profile_id,
    status
FROM migration_exceptions
ORDER BY exception_key;

\echo 'Dana Staff Created active memberships; expected zero rows'
SELECT hm.*
FROM profiles AS p
JOIN household_memberships AS hm
    ON hm.profile_id = p.id
WHERE p.display_name = 'Dana Staff Created'
  AND hm.status = 'active';

\echo 'Jordan Lee active memberships; expected zero rows'
SELECT
    p.id AS profile_id,
    p.display_name,
    hm.*
FROM profiles AS p
JOIN household_memberships AS hm
    ON hm.profile_id = p.id
WHERE p.display_name = 'Jordan Lee'
  AND hm.status = 'active';

\echo 'Final constraint summary checks'
SELECT
    'validation functions exist' AS check_name,
    count(*) = 5 AS passed,
    count(*) AS actual
FROM pg_proc AS p
JOIN pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
      'assert_household_exactly_one_active_owner',
      'assert_profile_has_no_active_membership_when_archived',
      'check_household_owner_after_membership_change',
      'check_household_owner_after_household_change',
      'check_profile_membership_after_profile_change'
  );

SELECT
    'deferred constraint triggers installed' AS check_name,
    count(*) = 3
        AND bool_and(tgconstraint <> 0)
        AND bool_and(tgdeferrable)
        AND bool_and(tginitdeferred)
        AND bool_and(tgenabled = 'O') AS passed,
    count(*) AS actual
FROM pg_trigger
WHERE tgname IN (
    'household_memberships_exactly_one_owner_trigger',
    'households_exactly_one_owner_trigger',
    'profiles_no_active_membership_when_archived_trigger'
)
  AND NOT tgisinternal;

SELECT
    'every active household has exactly one active owner' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM households AS h
        LEFT JOIN household_memberships AS hm
            ON hm.household_id = h.id
           AND hm.status = 'active'
           AND hm.role = 'owner'
        WHERE h.status = 'active'
        GROUP BY h.id
        HAVING count(hm.id) <> 1
    ) AS passed;

SELECT
    'archived households have no active memberships' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM households AS h
        JOIN household_memberships AS hm
            ON hm.household_id = h.id
        WHERE h.status = 'archived'
          AND hm.status = 'active'
    ) AS passed;

SELECT
    'archived profiles have no active memberships' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM household_memberships AS hm
        JOIN profiles AS p
            ON p.id = hm.profile_id
        WHERE hm.status = 'active'
          AND p.status = 'archived'
    ) AS passed;

SELECT
    'profile-level unresolved exception records have no active memberships' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM migration_exceptions AS me
        JOIN profiles AS p
            ON p.id = me.profile_id
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE me.status = 'open'
          AND hm.status = 'active'
    ) AS passed;

SELECT
    'group-level unresolved exception records have no active memberships' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM migration_exceptions AS me
        JOIN profiles AS p
            ON p.login_id = me.legacy_login_id
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE me.status = 'open'
          AND me.legacy_login_id IS NOT NULL
          AND hm.status = 'active'
    ) AS passed;

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
    'Jordan Lee profiles have no active membership' AS check_name,
    NOT EXISTS (
        SELECT 1
        FROM profiles AS p
        JOIN household_memberships AS hm
            ON hm.profile_id = p.id
        WHERE p.display_name = 'Jordan Lee'
          AND hm.status = 'active'
    ) AS passed;
