-- Final constraint-hardening phase for the household access model.
--
-- This migration runs after expand, deterministic backfill, and validation. It
-- does not remove the legacy model, switch application reads or writes, or make
-- the new model the only rollback path. The new model remains additive.
--
-- Constraint triggers validate the final transaction state. The existing
-- partial unique index enforces at most one active owner immediately; the
-- deferred triggers enforce that every active household has at least one active
-- owner at commit. Together, they enforce exactly one active owner. The same
-- deferred checks also prevent archived households and archived profiles from
-- retaining active memberships.
--
-- Deferred execution allows valid multi-statement workflows such as household
-- creation and owner transfer. Application service operations must still use
-- transactions, row locking, and authorization checks; database constraints are
-- a final safety net, not a replacement for authorization logic.

BEGIN;

DO $$
DECLARE
    invalid_household_count integer;
BEGIN
    SELECT count(*)
    INTO invalid_household_count
    FROM (
        SELECT h.id
        FROM households AS h
        LEFT JOIN household_memberships AS hm
            ON hm.household_id = h.id
           AND hm.status = 'active'
           AND hm.role = 'owner'
        WHERE h.status = 'active'
        GROUP BY h.id
        HAVING count(hm.id) <> 1
    ) AS invalid_households;

    IF invalid_household_count > 0 THEN
        RAISE EXCEPTION
            'cannot install final owner constraint: % active household(s) do not have exactly one active owner; run scripts/verify-final-constraints.sql for details',
            invalid_household_count
            USING ERRCODE = '23514';
    END IF;
END $$;

DO $$
DECLARE
    invalid_membership_count integer;
BEGIN
    SELECT count(*)
    INTO invalid_membership_count
    FROM household_memberships AS hm
    JOIN households AS h
        ON h.id = hm.household_id
    WHERE hm.status = 'active'
      AND h.status = 'archived';

    IF invalid_membership_count > 0 THEN
        RAISE EXCEPTION
            'cannot install final owner constraint: % active membership(s) belong to archived households; run scripts/verify-final-constraints.sql for details',
            invalid_membership_count
            USING ERRCODE = '23514';
    END IF;
END $$;

DO $$
DECLARE
    invalid_profile_count integer;
BEGIN
    SELECT count(*)
    INTO invalid_profile_count
    FROM household_memberships AS hm
    JOIN profiles AS p
        ON p.id = hm.profile_id
    WHERE hm.status = 'active'
      AND p.status = 'archived';

    IF invalid_profile_count > 0 THEN
        RAISE EXCEPTION
            'cannot install final owner constraint: % active membership(s) reference archived profiles; run scripts/verify-final-constraints.sql for details',
            invalid_profile_count
            USING ERRCODE = '23514';
    END IF;
END $$;

-- This function evaluates the transaction's final state when invoked by
-- deferred constraint triggers. It intentionally does not enforce the owner
-- invariant statement-by-statement, so valid owner-transfer transactions can
-- temporarily pass through zero-owner states before commit.
CREATE OR REPLACE FUNCTION public.assert_household_exactly_one_active_owner(
    target_household_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    target_status text;
    active_owner_count integer;
    active_membership_count integer;
BEGIN
    IF target_household_id IS NULL THEN
        RETURN;
    END IF;

    SELECT status
    INTO target_status
    FROM households
    WHERE id = target_household_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT count(*)
    INTO active_membership_count
    FROM household_memberships
    WHERE household_id = target_household_id
      AND status = 'active';

    IF target_status = 'active' THEN
        SELECT count(*)
        INTO active_owner_count
        FROM household_memberships
        WHERE household_id = target_household_id
          AND status = 'active'
          AND role = 'owner';

        IF active_owner_count <> 1 THEN
            RAISE EXCEPTION
                'household % must have exactly one active owner; found %',
                target_household_id,
                active_owner_count
                USING
                    ERRCODE = '23514',
                    CONSTRAINT = 'households_exactly_one_active_owner';
        END IF;
    ELSIF target_status = 'archived' AND active_membership_count <> 0 THEN
        RAISE EXCEPTION
            'archived household % must have zero active memberships; found %',
            target_household_id,
            active_membership_count
            USING
                ERRCODE = '23514',
                CONSTRAINT = 'archived_households_no_active_memberships';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.assert_profile_has_no_active_membership_when_archived(
    target_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    target_status text;
    active_membership_count integer;
BEGIN
    IF target_profile_id IS NULL THEN
        RETURN;
    END IF;

    SELECT status
    INTO target_status
    FROM profiles
    WHERE id = target_profile_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF target_status = 'archived' THEN
        SELECT count(*)
        INTO active_membership_count
        FROM household_memberships
        WHERE profile_id = target_profile_id
          AND status = 'active';

        IF active_membership_count <> 0 THEN
            RAISE EXCEPTION
                'archived profile % must have zero active memberships; found %',
                target_profile_id,
                active_membership_count
                USING
                    ERRCODE = '23514',
                    CONSTRAINT = 'archived_profiles_no_active_memberships';
        END IF;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_household_owner_after_membership_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM public.assert_household_exactly_one_active_owner(NEW.household_id);
        PERFORM public.assert_profile_has_no_active_membership_when_archived(NEW.profile_id);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        PERFORM public.assert_household_exactly_one_active_owner(OLD.household_id);
        PERFORM public.assert_profile_has_no_active_membership_when_archived(OLD.profile_id);
        RETURN OLD;
    ELSE
        PERFORM public.assert_household_exactly_one_active_owner(OLD.household_id);
        PERFORM public.assert_profile_has_no_active_membership_when_archived(OLD.profile_id);

        IF NEW.household_id IS DISTINCT FROM OLD.household_id THEN
            PERFORM public.assert_household_exactly_one_active_owner(NEW.household_id);
        END IF;

        IF NEW.profile_id IS DISTINCT FROM OLD.profile_id THEN
            PERFORM public.assert_profile_has_no_active_membership_when_archived(NEW.profile_id);
        END IF;

        RETURN NEW;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_household_owner_after_household_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.assert_household_exactly_one_active_owner(NEW.id);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.check_profile_membership_after_profile_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM public.assert_profile_has_no_active_membership_when_archived(NEW.id);
    RETURN NEW;
END;
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'household_memberships_exactly_one_owner_trigger'
          AND tgrelid = 'household_memberships'::regclass
          AND NOT tgisinternal
    ) THEN
        CREATE CONSTRAINT TRIGGER household_memberships_exactly_one_owner_trigger
        AFTER INSERT OR UPDATE OR DELETE
        ON household_memberships
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION public.check_household_owner_after_membership_change();
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'households_exactly_one_owner_trigger'
          AND tgrelid = 'households'::regclass
          AND NOT tgisinternal
    ) THEN
        CREATE CONSTRAINT TRIGGER households_exactly_one_owner_trigger
        AFTER INSERT OR UPDATE OF status
        ON households
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION public.check_household_owner_after_household_change();
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_trigger
        WHERE tgname = 'profiles_no_active_membership_when_archived_trigger'
          AND tgrelid = 'profiles'::regclass
          AND NOT tgisinternal
    ) THEN
        CREATE CONSTRAINT TRIGGER profiles_no_active_membership_when_archived_trigger
        AFTER INSERT OR UPDATE OF status
        ON profiles
        DEFERRABLE INITIALLY DEFERRED
        FOR EACH ROW
        EXECUTE FUNCTION public.check_profile_membership_after_profile_change();
    END IF;
END $$;

COMMIT;
