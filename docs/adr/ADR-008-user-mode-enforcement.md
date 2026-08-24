# ADR-008: Every File Hub read runs in USER_MODE, and tests run as a permission-set user

## Status

**Accepted**

## Date

2026-05-20 (hardening pass), reinforced 2026-07-06

## Author

Mustafa Aksu

## Context

Apex runs in system context by default. `with sharing` restrains **record**
visibility, but it does not enforce **object and field** permissions: a class
declared `with sharing` will still happily read a field the running user has no
access to and return it to the browser.

For a feature that surfaces partner compliance documents, that gap is the
difference between a permission set that describes access and one that enforces
it.

## Decision

Enforce CRUD and FLS at every boundary:

- Dynamic queries use `Database.query(soql, AccessLevel.USER_MODE)`.
- Static queries use `WITH USER_MODE`.
- Writes use `insert as user`.

And — the part that makes it real — **tests assign the `File_Hub_User`
permission set to their run-as users.** A test that runs as an admin proves
nothing about enforcement, because an admin passes every check.

The permission set therefore grants exactly what the feature touches:
`File_Hub_Entry__c` CRUD, and read on the related `Reseller__c` and `Loan__c`
records. If a field is added to a query without being added to the permission
set, a test fails.

## Alternatives Considered

- **`with sharing` alone.** Rejected: it addresses record access and leaves
  object and field access unchecked.
- **Manual `Schema.sObjectType.<X>.isAccessible()` checks.** The pre-USER_MODE
  approach. Rejected: verbose, easy to forget on a new query, and it verifies
  access without actually running the query under it.
- **Testing as an administrator.** Rejected: it is why enforcement gaps survive
  a green test suite.

## Consequences

- The permission set is a real contract, verified by the test suite rather than
  asserted in a document.
- A `System.QueryException` on a missing permission is now a **correct** failure
  and points at the permission set.
- Adding a field to a query means adding it to the permission set. That coupling
  is the feature, not the friction.
- Two adjacent traps were hit while building this and are recorded in
  `FILE-HUB.md` §12: `objectPermissions` blocks in a permission set must be
  contiguous, and required fields cannot carry explicit `fieldPermissions`
  because access is automatic.

## References

- `force-app/main/default/classes/controller/FileHubController.cls`
- `force-app/main/default/permissionsets/`
- `FILE-HUB.md` §7, §9, §12
- Commit `security(apex): explicit sharing declarations + remove dead code`
