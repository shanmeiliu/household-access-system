\echo 'Eligible demo login account IDs'

SELECT
    la.id AS login_account_id,
    p.display_name,
    la.email,
    la.status,
    hm.household_id
FROM login_accounts AS la
JOIN profiles AS p
    ON p.id = la.profile_id
JOIN household_memberships AS hm
    ON hm.profile_id = p.id
JOIN households AS h
    ON h.id = hm.household_id
WHERE la.status = 'active'
  AND p.status = 'active'
  AND hm.status = 'active'
  AND h.status = 'active'
ORDER BY p.display_name, la.id;
