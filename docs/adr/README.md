# Architecture Decision Records

Nine features, sixty Apex classes, fourteen Lightning Web Components. These
records say why the code looks the way it does — what the constraint was, what
was chosen, what else was on the table, and what the choice costs.

They are written retrospectively, but from the code and the commit history
rather than from memory. Every claim points at a file you can open.

## Index

| # | Decision | The constraint behind it |
|---|---|---|
| [001](ADR-001-kevin-ohara-triggerhandler.md) | One trigger per object, Kevin O'Hara handler framework | Six automated objects, several writing to each other |
| [002](ADR-002-layered-apex-folders.md) | Apex organised by role, not by feature | Sixty classes in a flat folder communicate nothing |
| [003](ADR-003-api-keys-in-hierarchy-custom-setting.md) | API keys in a hierarchical custom setting | They were hardcoded first — and history keeps what the tree forgets |
| [004](ADR-004-visualforce-bridge-for-maps-sdk.md) | The Maps SDK is hosted in a Visualforce page | Lightning Web Security blocks it inside an LWC |
| [005](ADR-005-prompt-template-as-metadata.md) | The Einstein Prompt Template is metadata | A prompt authored in a UI is untracked business logic |
| [006](ADR-006-compliance-rules-in-custom-metadata.md) | Compliance requirements are Custom Metadata | Rules change on a business timetable, not a release one |
| [007](ADR-007-private-sharing-with-apex-managed-shares.md) | File Hub entries are Private with Apex-managed shares | "Sent to this user" is not a sharing-rule criterion |
| [008](ADR-008-user-mode-enforcement.md) | Every read runs in `USER_MODE`, tests run as a permset user | `with sharing` does not enforce field access |
| [009](ADR-009-orphan-cleanup-on-contentdocument-delete.md) | Orphan cleanup lives on the `ContentDocument` trigger | Files are deleted from four places, only one of them ours |
| [010](ADR-010-lms-instead-of-polling.md) | Sibling components sync over Lightning Message Service | Siblings have no parent to lift state into |
| [011](ADR-011-platform-event-with-poll-fallback.md) | Platform Event for push, with a poll as the floor | Streaming silence is indistinguishable from no news |
| [012](ADR-012-retry-with-audit-log.md) | Failed syncs retry on a schedule and every attempt is logged | A loan that exists here and not there looks fine on both screens |
| [013](ADR-013-queueable-callout-with-mock.md) | Callouts run in a Queueable, tested against a committed mock | A live endpoint refuses to be unreliable on demand |
| [014](ADR-014-graceful-degradation-on-ai-and-key-absence.md) | Missing AI or key degrades, never fails | An unconfigured org is not an exceptional condition |

## Two pairs worth reading together

**ADR-010 and its sibling.** This project pushes cross-component updates over
Lightning Message Service and explicitly rejects polling. The sibling
[urlashoes-sandbox](https://github.com/aksumustafa1625/urlashoes-sandbox)
**does** poll, and its ADR-003 explains why: there the change originates in the
platform's own roll-up, so no component is in a position to announce it. Same
technique, opposite circumstances, both written down.

**ADR-003 and the honesty question.** The keys in this project were hardcoded
before they were configured properly. The record says so. An architecture
document that only describes the final shape teaches nothing about how the shape
was arrived at — and the correction is the part worth reading.

## Format

Status · Date · Author · Context · Decision · Alternatives Considered ·
Consequences · References.

The same structure is used across the sibling projects, so a reader moving
between repositories reads the same shape each time.
