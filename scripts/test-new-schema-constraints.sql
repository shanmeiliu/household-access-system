\echo 'Begin rollback-only new schema constraint test'
BEGIN;

\echo 'Insert temporary valid rows'
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
        '99999999-9999-9999-9999-999999999001',
        'Temporary Owner',
        '1991-01-01',
        NULL,
        NULL,
        NULL
    ),
    (
        '99999999-9999-9999-9999-999999999002',
        'Temporary Member',
        '1992-02-02',
        NULL,
        NULL,
        NULL
    ),
    (
        '99999999-9999-9999-9999-999999999003',
        'Temporary External Identity Duplicate',
        '1993-03-03',
        NULL,
        NULL,
        NULL
    );

INSERT INTO households (id)
VALUES ('99999999-9999-9999-9999-999999999101');

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES (
    '99999999-9999-9999-9999-999999999201',
    '99999999-9999-9999-9999-999999999101',
    '99999999-9999-9999-9999-999999999001',
    'owner'
);

INSERT INTO login_accounts (
    id,
    profile_id,
    email,
    identity_provider,
    external_subject
)
VALUES (
    '99999999-9999-9999-9999-999999999301',
    '99999999-9999-9999-9999-999999999002',
    'temporary.member@example.test',
    'test-idp',
    'temporary-member'
);

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES (
    '99999999-9999-9999-9999-999999999202',
    '99999999-9999-9999-9999-999999999101',
    '99999999-9999-9999-9999-999999999002',
    'member'
);

DO $$
BEGIN
    BEGIN
        INSERT INTO login_accounts (id, profile_id)
        VALUES (
            '99999999-9999-9999-9999-999999999302',
            '99999999-9999-9999-9999-999999999002'
        );
        RAISE EXCEPTION 'expected duplicate login account to be rejected';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'constraint worked: second login-account row for same profile was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO household_memberships (
            id,
            household_id,
            profile_id,
            role
        )
        VALUES (
            '99999999-9999-9999-9999-999999999203',
            '99999999-9999-9999-9999-999999999101',
            '99999999-9999-9999-9999-999999999002',
            'member'
        );
        RAISE EXCEPTION 'expected duplicate active membership to be rejected';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'constraint worked: second active membership for same profile was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        UPDATE household_memberships
        SET role = 'owner'
        WHERE id = '99999999-9999-9999-9999-999999999202';
        RAISE EXCEPTION 'expected second active owner to be rejected';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'constraint worked: second active owner in same household was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO login_accounts (
            id,
            profile_id,
            status
        )
        VALUES (
            '99999999-9999-9999-9999-999999999303',
            '99999999-9999-9999-9999-999999999001',
            'pending'
        );
        RAISE EXCEPTION 'expected invalid login status to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: invalid login status was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO login_accounts (
            id,
            profile_id,
            status,
            disabled_at
        )
        VALUES (
            '99999999-9999-9999-9999-999999999304',
            '99999999-9999-9999-9999-999999999001',
            'active',
            now()
        );
        RAISE EXCEPTION 'expected active login with disabled_at to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: active login with disabled_at was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO household_memberships (
            id,
            household_id,
            profile_id,
            role,
            status
        )
        VALUES (
            '99999999-9999-9999-9999-999999999204',
            '99999999-9999-9999-9999-999999999101',
            '99999999-9999-9999-9999-999999999001',
            'member',
            'removed'
        );
        RAISE EXCEPTION 'expected removed membership without removed_at to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: removed membership without removed_at was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO login_accounts (
            id,
            profile_id,
            identity_provider
        )
        VALUES (
            '99999999-9999-9999-9999-999999999305',
            '99999999-9999-9999-9999-999999999001',
            'test-idp'
        );
        RAISE EXCEPTION 'expected identity provider without external subject to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: identity provider without external subject was rejected';
    END;
END $$;

DO $$
BEGIN
    BEGIN
        INSERT INTO login_accounts (
            id,
            profile_id,
            identity_provider,
            external_subject
        )
        VALUES (
            '99999999-9999-9999-9999-999999999306',
            '99999999-9999-9999-9999-999999999003',
            'test-idp',
            'temporary-member'
        );
        RAISE EXCEPTION 'expected duplicate non-deleted external identity to be rejected';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'constraint worked: duplicate non-deleted external identity was rejected';
    END;
END $$;

\echo 'Temporary valid login accounts'
SELECT id, profile_id, email, identity_provider, external_subject, status
FROM login_accounts
WHERE id = '99999999-9999-9999-9999-999999999301';

\echo 'Temporary valid households'
SELECT id, status
FROM households
WHERE id = '99999999-9999-9999-9999-999999999101';

\echo 'Temporary valid memberships'
SELECT id, household_id, profile_id, role, status
FROM household_memberships
WHERE id IN (
    '99999999-9999-9999-9999-999999999201',
    '99999999-9999-9999-9999-999999999202'
)
ORDER BY id;

ROLLBACK;
\echo 'Constraint test rows were rolled back; no data was left behind.'
