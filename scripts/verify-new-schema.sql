\echo 'Required tables'
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'profiles',
      'login_accounts',
      'households',
      'household_memberships'
  )
ORDER BY table_name;

\echo 'Legacy profile columns retained'
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'profiles'
  AND column_name IN ('login_id', 'login_email', 'owner_name')
ORDER BY column_name;

\echo 'Foreign keys'
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name,
    confrelid::regclass AS referenced_table
FROM pg_constraint
WHERE contype = 'f'
  AND conname IN (
      'login_accounts_profile_id_fkey',
      'household_memberships_profile_id_fkey',
      'household_memberships_household_id_fkey'
  )
ORDER BY constraint_name;

\echo 'One login-account row per profile'
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name
FROM pg_constraint
WHERE contype = 'u'
  AND conname = 'login_accounts_profile_id_key';

\echo 'Partial unique indexes'
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
      'uq_household_memberships_active_profile',
      'uq_household_memberships_active_owner'
  )
ORDER BY indexname;

\echo 'Check constraints'
SELECT
    conname AS constraint_name,
    conrelid::regclass AS table_name
FROM pg_constraint
WHERE contype = 'c'
  AND conname IN (
      'login_accounts_status_check',
      'login_accounts_lifecycle_check',
      'login_accounts_identity_pair_check',
      'households_status_check',
      'households_lifecycle_check',
      'household_memberships_role_check',
      'household_memberships_status_check',
      'household_memberships_lifecycle_check'
  )
ORDER BY table_name, constraint_name;

\echo 'New table row counts before backfill'
SELECT 'login_accounts' AS table_name, count(*) AS row_count
FROM login_accounts
UNION ALL
SELECT 'households' AS table_name, count(*) AS row_count
FROM households
UNION ALL
SELECT 'household_memberships' AS table_name, count(*) AS row_count
FROM household_memberships
ORDER BY table_name;
