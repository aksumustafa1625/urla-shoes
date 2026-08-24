# ADR-010: Components stay in sync through Lightning Message Service, not by polling

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

On a Reseller record page, three components show the same underlying state from
different angles: the File Hub list, the compliance checklist, and the
partner score.

Uploading a document has to move all three at once. If a certificate is filed
and the score still reads 60%, the user does not conclude that the page is
stale — they conclude that the feature is broken.

The components are siblings. They have no parent to lift state into, so there is
no property to bind them together.

## Decision

Publish on a **Lightning Message Channel** when File Hub changes a document's
category or state. The checklist and the score subscribe and re-score
immediately. No polling, no refresh button, no timer.

## Alternatives Considered

- **Polling on an interval.** Rejected here: it costs a server round trip per
  component per tick to detect a change the publishing component already knows
  about. (The sibling `urlashoes-sandbox` project *does* poll — see its ADR-003
  — because there the change originates in the platform's own roll-up, and no
  component is in a position to announce it. Same technique, opposite
  circumstances.)
- **`refreshApex` on the sibling components.** Rejected: it requires a reference
  to the sibling's wire, which sibling components do not have.
- **Platform Events.** Rejected as the wrong scope: this is intra-page UI
  coordination in one browser tab, not a server-side event other systems care
  about. Platform Events *are* used in this project — see ADR-011 — where the
  producer and consumer really are separate.
- **A parent wrapper component holding the state.** Rejected: it would require
  the record page to be rebuilt around one container, which fights the Lightning
  App Builder layout the feature is dropped into.

## Consequences

- Updates are instant and cost nothing when nothing changes.
- The message channel is a contract between components, so its payload shape has
  to be treated as an interface.
- Coordination is limited to one browser tab, which is the correct scope for this
  problem and would be the wrong scope for a multi-user one.

## References

- `force-app/main/default/messageChannels/`
- `force-app/main/default/lwc/fileHub/`, `resellerComplianceChecklist/`, `complianceCockpit/`
- `FILE-HUB.md` §5, §10
- Sibling contrast: `urlashoes-sandbox` `docs/adr/ADR-003-change-signature-polling.md`
