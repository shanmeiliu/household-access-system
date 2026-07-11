\echo 'Total profiles'
SELECT count(*) AS total_profiles
FROM profiles;

\echo 'Profiles with NULL login_id'
SELECT count(*) AS profiles_with_null_login_id
FROM profiles
WHERE login_id IS NULL;

\echo 'Distinct non-null login groups'
SELECT count(DISTINCT login_id) AS distinct_non_null_login_groups
FROM profiles
WHERE login_id IS NOT NULL;

\echo 'Shared login groups'
SELECT login_id, count(*) AS profile_count
FROM profiles
WHERE login_id IS NOT NULL
GROUP BY login_id
HAVING count(*) > 1
ORDER BY login_id;

\echo 'Owner names referenced by multiple profiles'
SELECT owner_name, count(*) AS referencing_profiles
FROM profiles
WHERE owner_name IS NOT NULL
GROUP BY owner_name
HAVING count(*) > 1
ORDER BY owner_name;

\echo 'Owner names that do not match exactly one profile'
SELECT
    p.owner_name,
    count(DISTINCT possible_owner.id) AS matching_profiles
FROM profiles AS p
LEFT JOIN profiles AS possible_owner
    ON possible_owner.display_name = p.owner_name
WHERE p.owner_name IS NOT NULL
GROUP BY p.owner_name
HAVING count(DISTINCT possible_owner.id) <> 1
ORDER BY p.owner_name;
