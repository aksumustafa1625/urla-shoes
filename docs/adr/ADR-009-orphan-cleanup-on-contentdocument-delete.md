# ADR-009: Wrapper records are cleaned up by a ContentDocument trigger, not by the UI that created them

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

`File_Hub_Entry__c` wraps a Salesforce File: it carries the category, the
recipient, the read flag and the compliance linkage, and points at a
`ContentDocument`.

Files can be deleted from places File Hub does not control — the standard Files
UI, a related list, Data Loader, another Apex process. When that happens the
wrapper survives and points at nothing. The Cockpit then counts a compliance
document that no longer exists, and the partner's score is wrong in the
direction that matters.

Cleaning up in the File Hub component only covers deletions that go through File
Hub, which is the smallest of the available paths.

## Decision

Put the cleanup on the object being deleted. A **`before delete` trigger on
`ContentDocument`** calls `FileHubService.deleteOrphanedEntries`, so every
deletion path — UI, API, Data Loader, Apex — removes the wrapper entries that
referenced the file.

`FileHubService` is declared **`inherited sharing`** so that when it is invoked
from trigger context it can reach every orphan, rather than only those visible
to whoever pressed delete. That is deliberate: a cleanup that only removes the
orphans the deleting user can see leaves the rest behind and the score still
wrong.

## Alternatives Considered

- **Delete the entry from the File Hub LWC.** Rejected: covers one deletion path
  out of four.
- **A scheduled job that sweeps orphans nightly.** Rejected: compliance scores
  would be wrong for up to a day, and the Cockpit's whole value is being current.
- **A formula or validation that hides orphaned entries.** Rejected: it hides
  the symptom and leaves the rows, so reports and the API still see them.
- **`after delete` instead of `before delete`.** Rejected: the relationship
  needed to find the orphans is easier to resolve while the parent still exists.

## Consequences

- Entries cannot outlive their file, whatever deletes it.
- One trigger exists on a **standard** object, which is worth knowing before
  adding another automation there.
- The `inherited sharing` declaration is a deliberate widening in trigger
  context, and is recorded here so it is not mistaken for an oversight.
- Compliance scores are correct immediately after a deletion, with no sweep.

## References

- `force-app/main/default/triggers/ContentDocumentTrigger.trigger`
- `force-app/main/default/classes/services/FileHubService.cls`
- `FILE-HUB.md` §7 "Ghost-record prevention"
- Commit `Harden File Hub: FLS/CRUD enforcement + ghost-record orphan prevention`
