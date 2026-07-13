# Migration Plan

The migration uses an expand-and-contract approach. Unexplained new-model access must never be broader than legacy access. Intentional authorization expansions must be explicitly modeled, reviewed, tested, and enabled through controlled rollout. Ambiguous legacy records should be routed to an exception table or migration review queue rather than guessed.

## Legacy Data Baseline

The executable legacy fixture in `migrations/001_legacy_schema.sql` includes shared login-based households, profiles with no login, owners without login, members unable to have independent credentials, and ambiguous text owner names.

These fixtures will later be used to validate backfill behavior, authorization comparison, and exception handling before the new model becomes authoritative.

## Expand

Objective: add the new model without changing production behavior.

Database changes:

- create nullable `login_accounts`, `households`, and `household_memberships` structures
- `002_new_schema.sql` implements empty `login_accounts`, `households`, and `household_memberships` tables
- add safe foreign keys and check constraints for the expanded model
- enforce at most one active membership per profile
- enforce at most one active owner per household
- do not add the exactly-one-owner trigger until after backfill and validation
- do not backfill legacy rows or switch authorization behavior
- add indexes needed for backfill and reconciliation
- add nullable foreign-key columns and, where appropriate, add foreign-key constraints using `NOT VALID`, then validate them after backfill
- avoid request-path table rewrites

Application behavior:

- continue legacy reads and writes
- keep authorization based on the legacy path
- add instrumentation around legacy household assumptions

Validation or monitoring:

- count profiles by null and non-null legacy `login_id`
- find duplicate or shared identifiers
- inventory owner-name values that do not map cleanly to profiles

Rollback approach:

- stop using the new structures
- drop unused new objects only if no backfill or dual-write depends on them

Security risk:

- low if the new schema is not consulted for authorization yet

## Backfill

Objective: populate deterministic new records from legacy data.

Database changes:

- create household records for unambiguous legacy household groups
- `003_backfill.sql` creates stable mappings from legacy login groups to new households
- identify owners through exact unique profile-name matches
- include owners without login IDs when deterministic
- create profile memberships with `owner` or `member` roles where ownership is known
- create login accounts only from unambiguous login-email rows
- quarantine ambiguous groups in `migration_exceptions`
- leave Dana Staff Created and the ambiguous Jordan Lee group outside new-model authorization
- remain idempotent through `migration_household_map` and stable exception keys

Application behavior:

- continue serving legacy reads
- run idempotent migration jobs in bounded batches
- avoid guessing when legacy rows conflict

Validation or monitoring:

- profiles missing membership
- households missing owner
- households with multiple owners
- login/profile mismatches
- profiles assigned to more than one active household
- backfill job retries and dead-letter counts

Rollback approach:

- re-run deterministic jobs after fixes
- clear or supersede generated rows for affected batches
- keep legacy data as source of truth during this phase

Security risk:

- medium; incorrect backfill can affect later authorization, so incomplete or conflicting rows must fail closed

## Dual-write

Objective: keep the legacy model and new model synchronized for new writes.

Database changes:

- add indexes or constraints that support idempotent writes
- defer hard constraints that would fail existing unresolved data

Application behavior:

- write to the legacy model and the new model inside controlled service operations
- record dual-write failures for repair
- keep legacy reads as the primary response path

Validation or monitoring:

- dual-write success and failure rates
- divergence between legacy and new household membership state
- login/profile mismatch counts
- owner state mismatch counts

Rollback approach:

- disable the dual-write feature flag
- repair or discard new-model writes that were not promoted to source of truth

Security risk:

- medium; divergence must not be used to broaden access

## Shadow Read

Objective: compare new reads and authorization decisions without serving them.

Database changes:

- none required beyond read indexes and comparison support

Application behavior:

- execute new authorization queries in shadow mode
- serve the legacy result
- compare allow/deny decisions and manageable profile sets

Validation or monitoring:

- legacy-versus-new authorization decision differences
- new allow where legacy denies, which is a potential security leak and highest severity
- new deny where legacy allows, which is a migration correctness or availability issue
- query latency and error rates
- exception queue burn-down

Rollback approach:

- disable shadow reads
- continue legacy behavior

Security risk:

- low for users because shadow results are not served; high-signal differences must still be reviewed before rollout

## Switch Reads

Objective: begin serving new authorization and data reads for controlled traffic.

Database changes:

- add validated indexes required for production read paths
- keep legacy columns available for rollback

Application behavior:

- enable new reads behind feature flags
- start with internal users, low-risk cohorts, or limited traffic
- fail closed when new membership information is missing
- never fall back from a new-model deny to a broader legacy allow without explicit compatibility policy
- require intentional authorization expansions to be modeled, reviewed, tested, and enabled through controlled rollout

Validation or monitoring:

- authorization deny rates
- support events related to missing household access
- new query latency
- comparison metrics retained for non-served traffic

Rollback approach:

- turn off the read flag and return selected traffic to legacy reads
- keep dual-write active until source-of-truth transition is complete

Security risk:

- high; this is the first user-visible authorization change and needs careful feature-flag control

## Validate

Objective: harden the model once data is clean and new reads are trusted.

Database changes:

- create unique indexes concurrently where needed
- add `NOT VALID` constraints, then `VALIDATE CONSTRAINT`
- add a unique constraint on `login_accounts(profile_id)`
- add partial unique indexes for active membership rules
- introduce deferred validation or constraint triggers for exactly-one-owner semantics

PostgreSQL concurrent index creation must run outside a transaction and should be deployed as a separate operational migration step.

Application behavior:

- rely on centralized service operations for ownership and membership mutations
- stop writes that would create unresolved legacy-only state

Validation or monitoring:

- zero households missing active owner
- zero households with multiple active owners
- zero active profiles with multiple active households
- zero profiles with multiple login-account records
- constraint validation duration and lock impact

Rollback approach:

- pause constraint hardening before contract
- drop newly added constraints only if they block valid business behavior and a forward fix is not possible

Security risk:

- medium; incorrect constraints can create availability issues, but they reduce long-term authorization risk

## Contract

Objective: remove legacy authorization dependence after the rollback window.

Database changes:

- remove legacy authorization reads
- stop legacy writes
- remove the overloaded `login_id` only after rollback is no longer required
- drop temporary migration tables after audit retention needs are satisfied

Application behavior:

- use the new model as the only authorization source
- remove compatibility logic and comparison code

Validation or monitoring:

- no reads from legacy authorization fields
- no writes to legacy household-grouping fields
- clean decision metrics before removal

Rollback approach:

- after contract, rollback is primarily restore-or-forward-fix; this phase should wait until operational confidence is high

Security risk:

- medium; removing compatibility code is safer long term, but the rollback path narrows

## Reconciliation Metrics

Track these metrics throughout backfill, dual-write, and rollout:

- profiles missing membership
- households missing owner
- households with multiple owners
- login/profile mismatches
- legacy-versus-new authorization decision differences
- new-model allows where legacy denies, which are potential security leaks and highest severity
- new-model denies where legacy allows, which are migration correctness or availability issues
- dual-write failures
- unresolved exception queue count
- stale sessions after login disablement

Ambiguous rows should be preserved for manual review with enough context to make a deterministic decision later. Guessing during migration is a security risk because it can silently create cross-household access.
