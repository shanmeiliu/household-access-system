-- All names, email addresses, dates, and identifiers in this file are
-- fictional test data created solely to demonstrate legacy migration cases.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    display_name TEXT NOT NULL,
    date_of_birth DATE NULL,
    login_id UUID NULL,
    login_email TEXT NULL,
    owner_name TEXT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT profiles_status_check CHECK (status IN ('active', 'archived'))
);

CREATE INDEX IF NOT EXISTS idx_profiles_login_id
    ON profiles(login_id);

CREATE INDEX IF NOT EXISTS idx_profiles_status
    ON profiles(status);

INSERT INTO profiles (
    id,
    display_name,
    date_of_birth,
    login_id,
    login_email,
    owner_name
)
VALUES
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
        'Alice Parent',
        '1980-01-15',
        '11111111-1111-1111-1111-111111111111',
        'alice@example.test',
        'Alice Parent'
    ),
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
        'Bob Parent',
        '1979-05-20',
        '11111111-1111-1111-1111-111111111111',
        NULL,
        'Alice Parent'
    ),
    (
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa3',
        'Charlie Child',
        '2012-09-10',
        '11111111-1111-1111-1111-111111111111',
        NULL,
        'Alice Parent'
    ),
    (
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbb1',
        'Dana Staff Created',
        '1990-03-12',
        NULL,
        NULL,
        NULL
    ),
    (
        'cccccccc-cccc-cccc-cccc-ccccccccccc1',
        'Evelyn Owner',
        '1975-07-07',
        NULL,
        NULL,
        'Evelyn Owner'
    ),
    (
        'cccccccc-cccc-cccc-cccc-ccccccccccc2',
        'Frank Member',
        '1974-11-01',
        '22222222-2222-2222-2222-222222222222',
        'frank@example.test',
        'Evelyn Owner'
    ),
    (
        'cccccccc-cccc-cccc-cccc-ccccccccccc3',
        'Grace Child',
        '2015-04-24',
        '22222222-2222-2222-2222-222222222222',
        NULL,
        'Evelyn Owner'
    ),
    (
        'dddddddd-dddd-dddd-dddd-ddddddddddd1',
        'Henry Owner',
        '1982-08-08',
        '33333333-3333-3333-3333-333333333333',
        'henry@example.test',
        'Henry Owner'
    ),
    (
        'dddddddd-dddd-dddd-dddd-ddddddddddd2',
        'Iris Adult Member',
        '1984-12-18',
        '33333333-3333-3333-3333-333333333333',
        NULL,
        'Henry Owner'
    ),
    (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1',
        'Jordan Lee',
        '1978-02-02',
        '44444444-4444-4444-4444-444444444444',
        'jordan@example.test',
        'Jordan Lee'
    ),
    (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2',
        'Jordan Lee',
        '1981-06-06',
        '44444444-4444-4444-4444-444444444444',
        NULL,
        'Jordan Lee'
    ),
    (
        'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3',
        'Kelly Child',
        '2016-10-30',
        '44444444-4444-4444-4444-444444444444',
        NULL,
        'Jordan Lee'
    )
ON CONFLICT (id) DO NOTHING;

-- Iris Adult Member cannot have her own independent login without changing the
-- login_id value that also groups her with Henry Owner's household.

COMMIT;

-- Diagnostic: profiles with no login.
-- SELECT *
-- FROM profiles
-- WHERE login_id IS NULL;

-- Diagnostic: shared login groups.
-- SELECT login_id, count(*)
-- FROM profiles
-- WHERE login_id IS NOT NULL
-- GROUP BY login_id
-- HAVING count(*) > 1;

-- Diagnostic: owner names referenced by multiple rows. This shows repeated
-- references, but does not prove whether the owner name maps uniquely to a
-- profile.
-- SELECT owner_name, count(*)
-- FROM profiles
-- WHERE owner_name IS NOT NULL
-- GROUP BY owner_name
-- HAVING count(*) > 1;

-- Diagnostic: owner names that do not match exactly one profile.
-- SELECT
--     p.owner_name,
--     count(DISTINCT possible_owner.id) AS matching_profiles
-- FROM profiles AS p
-- LEFT JOIN profiles AS possible_owner
--     ON possible_owner.display_name = p.owner_name
-- WHERE p.owner_name IS NOT NULL
-- GROUP BY p.owner_name
-- HAVING count(DISTINCT possible_owner.id) <> 1;

-- Diagnostic: login IDs associated with multiple different login emails.
-- SELECT login_id, count(DISTINCT login_email)
-- FROM profiles
-- WHERE login_id IS NOT NULL
--   AND login_email IS NOT NULL
-- GROUP BY login_id
-- HAVING count(DISTINCT login_email) > 1;
