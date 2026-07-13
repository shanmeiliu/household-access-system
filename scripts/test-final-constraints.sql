\echo 'Begin rollback-only final constraint behavior test'
BEGIN;

\echo 'Valid household creation with deferred owner check'
INSERT INTO households (id)
VALUES ('88888888-8888-8888-8888-888888888101');

INSERT INTO profiles (
    id,
    display_name,
    date_of_birth,
    login_id,
    login_email,
    owner_name
)
VALUES (
    '88888888-8888-8888-8888-888888888001',
    'Final Constraint Valid Owner',
    '1990-01-01',
    NULL,
    NULL,
    NULL
);

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES (
    '88888888-8888-8888-8888-888888888201',
    '88888888-8888-8888-8888-888888888101',
    '88888888-8888-8888-8888-888888888001',
    'owner'
);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$
BEGIN
    BEGIN
        INSERT INTO households (id)
        VALUES ('88888888-8888-8888-8888-888888888102');

        SET CONSTRAINTS ALL IMMEDIATE;

        RAISE EXCEPTION 'expected active household without owner to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: active household without owner was rejected';
    END;
END $$;

SET CONSTRAINTS ALL DEFERRED;

DO $$
BEGIN
    BEGIN
        INSERT INTO households (id)
        VALUES ('88888888-8888-8888-8888-888888888103');

        INSERT INTO profiles (
            id,
            display_name,
            date_of_birth,
            login_id,
            login_email,
            owner_name
        )
        VALUES (
            '88888888-8888-8888-8888-888888888002',
            'Final Constraint Removed Owner',
            '1991-02-02',
            NULL,
            NULL,
            NULL
        );

        INSERT INTO household_memberships (
            id,
            household_id,
            profile_id,
            role
        )
        VALUES (
            '88888888-8888-8888-8888-888888888202',
            '88888888-8888-8888-8888-888888888103',
            '88888888-8888-8888-8888-888888888002',
            'owner'
        );

        UPDATE household_memberships
        SET status = 'removed',
            removed_at = now(),
            updated_at = now()
        WHERE id = '88888888-8888-8888-8888-888888888202';

        SET CONSTRAINTS ALL IMMEDIATE;

        RAISE EXCEPTION 'expected removing the only owner to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: removing the only owner was rejected';
    END;
END $$;

SET CONSTRAINTS ALL DEFERRED;

\echo 'Valid ownership transfer through temporary zero-owner state'
INSERT INTO households (id)
VALUES ('88888888-8888-8888-8888-888888888104');

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
        '88888888-8888-8888-8888-888888888003',
        'Final Constraint Owner A',
        '1992-03-03',
        NULL,
        NULL,
        NULL
    ),
    (
        '88888888-8888-8888-8888-888888888004',
        'Final Constraint Owner B',
        '1993-04-04',
        NULL,
        NULL,
        NULL
    );

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES
    (
        '88888888-8888-8888-8888-888888888203',
        '88888888-8888-8888-8888-888888888104',
        '88888888-8888-8888-8888-888888888003',
        'owner'
    ),
    (
        '88888888-8888-8888-8888-888888888204',
        '88888888-8888-8888-8888-888888888104',
        '88888888-8888-8888-8888-888888888004',
        'member'
    );

UPDATE household_memberships
SET role = 'member',
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888203';

UPDATE household_memberships
SET role = 'owner',
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888204';

SET CONSTRAINTS ALL IMMEDIATE;

SELECT
    household_id,
    count(*) AS active_owner_count
FROM household_memberships
WHERE household_id = '88888888-8888-8888-8888-888888888104'
  AND status = 'active'
  AND role = 'owner'
GROUP BY household_id;

SET CONSTRAINTS ALL DEFERRED;

\echo 'Archived household without active owner'
INSERT INTO households (
    id,
    status,
    archived_at
)
VALUES (
    '88888888-8888-8888-8888-888888888105',
    'archived',
    now()
);

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$
BEGIN
    BEGIN
        INSERT INTO households (id)
        VALUES ('88888888-8888-8888-8888-888888888106');

        INSERT INTO profiles (
            id,
            display_name,
            date_of_birth,
            login_id,
            login_email,
            owner_name
        )
        VALUES (
            '88888888-8888-8888-8888-888888888005',
            'Final Constraint Household Archive Owner',
            '1994-05-05',
            NULL,
            NULL,
            NULL
        );

        INSERT INTO household_memberships (
            id,
            household_id,
            profile_id,
            role
        )
        VALUES (
            '88888888-8888-8888-8888-888888888205',
            '88888888-8888-8888-8888-888888888106',
            '88888888-8888-8888-8888-888888888005',
            'owner'
        );

        UPDATE households
        SET status = 'archived',
            archived_at = now(),
            updated_at = now()
        WHERE id = '88888888-8888-8888-8888-888888888106';

        SET CONSTRAINTS ALL IMMEDIATE;

        RAISE EXCEPTION 'expected archiving household with active memberships to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: archiving a household with active memberships was rejected';
    END;
END $$;

SET CONSTRAINTS ALL DEFERRED;

\echo 'Valid household closure removes memberships before archive'
INSERT INTO households (id)
VALUES ('88888888-8888-8888-8888-888888888107');

INSERT INTO profiles (
    id,
    display_name,
    date_of_birth,
    login_id,
    login_email,
    owner_name
)
VALUES (
    '88888888-8888-8888-8888-888888888006',
    'Final Constraint Closure Owner',
    '1995-06-06',
    NULL,
    NULL,
    NULL
);

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES (
    '88888888-8888-8888-8888-888888888206',
    '88888888-8888-8888-8888-888888888107',
    '88888888-8888-8888-8888-888888888006',
    'owner'
);

UPDATE household_memberships
SET status = 'removed',
    removed_at = now(),
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888206';

UPDATE households
SET status = 'archived',
    archived_at = now(),
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888107';

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$
BEGIN
    BEGIN
        INSERT INTO households (id)
        VALUES ('88888888-8888-8888-8888-888888888108');

        INSERT INTO profiles (
            id,
            display_name,
            date_of_birth,
            login_id,
            login_email,
            owner_name
        )
        VALUES (
            '88888888-8888-8888-8888-888888888007',
            'Final Constraint Archived Profile Owner',
            '1996-07-07',
            NULL,
            NULL,
            NULL
        );

        INSERT INTO household_memberships (
            id,
            household_id,
            profile_id,
            role
        )
        VALUES (
            '88888888-8888-8888-8888-888888888207',
            '88888888-8888-8888-8888-888888888108',
            '88888888-8888-8888-8888-888888888007',
            'owner'
        );

        UPDATE profiles
        SET status = 'archived',
            updated_at = now()
        WHERE id = '88888888-8888-8888-8888-888888888007';

        SET CONSTRAINTS ALL IMMEDIATE;

        RAISE EXCEPTION 'expected archiving profile with active membership to be rejected';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'constraint worked: archiving a profile with active membership was rejected';
    END;
END $$;

SET CONSTRAINTS ALL DEFERRED;

\echo 'Valid profile archival removes membership before archive'
INSERT INTO households (id)
VALUES ('88888888-8888-8888-8888-888888888109');

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
        '88888888-8888-8888-8888-888888888008',
        'Final Constraint Archive Household Owner',
        '1997-08-08',
        NULL,
        NULL,
        NULL
    ),
    (
        '88888888-8888-8888-8888-888888888009',
        'Final Constraint Archive Member',
        '1998-09-09',
        NULL,
        NULL,
        NULL
    );

INSERT INTO household_memberships (
    id,
    household_id,
    profile_id,
    role
)
VALUES
    (
        '88888888-8888-8888-8888-888888888208',
        '88888888-8888-8888-8888-888888888109',
        '88888888-8888-8888-8888-888888888008',
        'owner'
    ),
    (
        '88888888-8888-8888-8888-888888888209',
        '88888888-8888-8888-8888-888888888109',
        '88888888-8888-8888-8888-888888888009',
        'member'
    );

UPDATE household_memberships
SET status = 'removed',
    removed_at = now(),
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888209';

UPDATE profiles
SET status = 'archived',
    updated_at = now()
WHERE id = '88888888-8888-8888-8888-888888888009';

SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

ROLLBACK;
\echo 'Final-constraint test rows were rolled back; no data was left behind.'
