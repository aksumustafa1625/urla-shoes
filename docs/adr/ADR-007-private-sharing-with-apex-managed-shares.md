# ADR-007: File Hub entries are Private, with access granted by Apex-managed shares

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

File Hub lets a user send a document to a specific colleague or partner contact.
The requirement is exact: **a recipient sees the files sent to them, and nothing
else.** Partner documents include compliance certificates and contracts, so
"everyone with access to the object can see every entry" is not an acceptable
approximation.

Salesforce offers several ways to narrow this, and most of them are the wrong
grain. Org-wide defaults and sharing rules operate on roles, owners and criteria
— structural facts about the org. Who a file was *sent to* is a per-record fact
known only at the moment of sending.

## Decision

Set the `File_Hub_Entry__c` org-wide default to **Private**, and grant read
access by inserting **`File_Hub_Entry__Share`** records in Apex when a file is
sent.

The corollary matters as much as the decision: the sharing model *must* be
Private for this to mean anything. Under Public Read/Write an Apex share is a
no-op, because everyone already has the access it would grant — a trap recorded
in `FILE-HUB.md` §12.

The controller runs `with sharing` so reads honour those shares. One narrow
operation — setting the read flag on an entry the user was legitimately shown —
uses a scoped bypass rather than widening the whole class.

## Alternatives Considered

- **Public Read/Write with filtering in SOQL.** Rejected: security by query.
  Any other query, report or Data Loader export sees everything.
- **Criteria-based sharing rules.** Rejected: they evaluate declaratively over
  field values; "was sent to this user" is not a criterion on the record.
- **Storing recipients in a multi-select field and filtering in the UI.**
  Rejected for the same reason as the first option, with worse ergonomics.

## Consequences

- Access is enforced by the platform, so it holds in reports, the API and Data
  Loader, not only in the component that was written to respect it.
- Sending a file is now a two-part transaction — create the entry, create the
  share — and both must succeed.
- Tests must run as a non-admin user to exercise sharing at all; an admin sees
  everything and would prove nothing.
- The `without sharing` bypass is a single narrow method. It is called out here
  precisely so it stays that way.

## References

- `force-app/main/default/objects/File_Hub_Entry__c/` — org-wide default
- `force-app/main/default/classes/services/FileHubSharingHelper.cls`
- `FILE-HUB.md` §7 "Security model", §12 item 6
