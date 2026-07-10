# Deletion Policy

This policy separates credentials, household access, and domain data. Deleting credentials, removing household access, and deleting or archiving profile records are three different actions.

## Terminology

- Login account: the ability to authenticate, represented by `login_accounts`.
- Profile: the person and retained business records, represented by `profiles`.
- Household membership: a profile's relationship to a household, represented by `household_memberships`.
- Disablement: preventing authentication while retaining the login record.
- Deletion: removing or anonymizing the login credential record according to policy.
- Archival: retaining domain records while removing them from active workflows.
- Removal: ending an active household membership.

## Login Disablement

Login disablement should be the first step when access must stop quickly. The system marks the login as `disabled`, prevents new authentication, and ensures authorization queries require `login_accounts.status = 'active'`.

Disabling a login does not delete the profile, remove household membership, or transfer ownership. If the disabled login belonged to an owner profile, the household can still have that owner because ownership is attached to the profile.

## Login Deletion

Login deletion removes authentication capability more permanently, but it is not the same as deleting the person. The profile and its business records remain unless a separate profile archival or deletion workflow applies.

A login deletion workflow should:

1. Disable the login.
2. Revoke active sessions and tokens.
3. Retain minimal audit metadata as required.
4. Remove or anonymize credential-facing identity fields according to retention policy.
5. Leave the profile lifecycle unchanged unless explicitly requested by a separate workflow.

## Session Revocation

Disabling or deleting a login must handle already-issued sessions. Options include server-side session invalidation, token revocation lists, short token lifetimes with forced revalidation, or identity-provider session revocation.

Authorization checks should not rely only on token claims if a login may have been disabled after token issuance. The active login state must be consulted or reliably reflected in session validation.

## Member Household Removal

Removing a member from a household changes `household_memberships`, not `profiles` or `login_accounts` by itself. A removed member's active login may continue to authenticate, but it must no longer grant access to the prior household.

If the profile belongs to no active household after removal, the login may authenticate but have no manageable household profiles unless another workflow assigns membership.

## Profile Archival

Profile archival removes the person from active business workflows while retaining records that may be needed for audit, continuity, or legal reasons. Authorization queries should require `profiles.status = 'active'` when returning manageable profiles.

Archiving a profile with an active login should first disable or delete the login, depending on the business case. Archiving a profile with active household membership should remove or close that membership through a service operation.

## Owner Transfer

An active household cannot lose its only owner. Before removing or archiving an owner profile, the system must either transfer ownership to another active member or close/archive the household.

Owner transfer must be transactional:

1. Lock the household and active memberships.
2. Verify the replacement owner is an active profile in the same household.
3. Change the current owner membership to `member` or `removed`, depending on the workflow.
4. Change the replacement membership to `owner`.
5. Commit only if exactly one active owner remains.

## Household Closure

Household closure is the explicit workflow for ending an active household when ownership cannot or should not be transferred. Closure should archive or remove active memberships according to business policy and prevent the household from granting access.

Closing a household should not automatically delete profiles or login accounts. Those actions remain separate workflows.

## Audit Trail

Security-sensitive lifecycle changes should produce audit records:

- login disabled
- login deleted or anonymized
- sessions revoked
- member removed from household
- profile archived
- owner transferred
- household closed

Audit records should identify the actor, target, timestamp, operation, and reason where available. The final audit schema is out of scope for this scaffold.

## Idempotency

Deletion and removal workflows should be idempotent. Repeating a request to disable an already disabled login, remove an already removed membership, or archive an already archived profile should not corrupt state or create duplicate side effects.

Idempotency is especially important for operator tooling, retrying background jobs, and identity-provider callbacks.

## Retention-Policy Caveats

This system resembles a healthcare domain, so retained business records may have privacy, security, and legal requirements. The design intentionally avoids claiming specific retention periods.

Final policy must be confirmed with privacy, security, and legal stakeholders. The technical model should support retention by separating authentication records from profile records and by preferring archival or soft deletion for domain data where appropriate.

## Example Workflows

### Disable a login immediately

1. Mark the login account `disabled`.
2. Revoke sessions and tokens.
3. Keep the profile and household membership unchanged.
4. Verify authorization queries no longer return manageable profiles for that login.

### Remove a non-owner member from a household

1. Mark the membership `removed`.
2. Keep the profile unless a separate archival request exists.
3. Keep or disable the login according to the business request.
4. Verify the login no longer has access to the removed household.

### Archive an owner profile

1. Begin owner-transfer or household-closure workflow.
2. Commit only when the active household will not be left ownerless.
3. Disable or delete the owner's login if one exists and access should stop.
4. Archive the profile after ownership or closure invariants are satisfied.

### Delete authentication but retain care records

1. Disable the login.
2. Revoke sessions.
3. Delete or anonymize credential-facing login fields according to policy.
4. Preserve the profile and domain records.
5. Keep audit metadata required to explain the deletion.
