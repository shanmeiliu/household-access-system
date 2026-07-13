-- Documentation-only owner-transfer transaction pattern.
--
-- This script is intentionally not wired into the Makefile. It demonstrates
-- the locking pattern application code should use when transferring ownership.
--
-- Row locks serialize competing owner transfers. Deferred constraint validation
-- checks the final state at commit, while the partial unique index prevents two
-- active owners. Application code must validate affected-row counts after each
-- UPDATE. Any failed validation must roll back the transaction.

-- BEGIN;

-- SELECT id
-- FROM households
-- WHERE id = $household_id
-- FOR UPDATE;

-- SELECT id
-- FROM household_memberships
-- WHERE household_id = $household_id
--   AND status = 'active'
-- FOR UPDATE;

-- UPDATE household_memberships
-- SET role = 'member',
--     updated_at = now()
-- WHERE household_id = $household_id
--   AND profile_id = $old_owner_profile_id
--   AND role = 'owner'
--   AND status = 'active';

-- UPDATE household_memberships
-- SET role = 'owner',
--     updated_at = now()
-- WHERE household_id = $household_id
--   AND profile_id = $new_owner_profile_id
--   AND role = 'member'
--   AND status = 'active';

-- COMMIT;
