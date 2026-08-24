# ADR-012: Failed loan syncs retry on a schedule, and every attempt is written down

## Status

**Accepted**

## Date

2026-04-19

## Author

Mustafa Aksu

## Context

Closing an Opportunity as Won creates a `Loan__c` and syncs it to an external
core system over an async callout. That callout will fail — the remote system
will be down, slow, or will reject a payload — and the question is what the org
does about it.

The default behaviour of a Queueable that throws is that the record stays
unsynced and nobody finds out. The business consequence is a loan that exists in
Salesforce, does not exist in the core system, and looks fine on both screens.

## Decision

Three parts, and all three are needed:

1. **Retry on a schedule.** `LoanSyncRetryScheduler` picks up records left in a
   failed state and tries again, so a transient outage resolves itself without a
   human.
2. **Audit every attempt.** `Loan_Sync_Log__c` records each try — when, what was
   sent, what came back. Not just failures: a successful sync that took four
   attempts is a different operational fact from one that took one.
3. **Surface the state.** The `loanSyncDashboard` component shows what is
   pending, what is failing and what has been retried, so the answer to "did it
   go through" is a screen rather than a debug log.

The retry is bounded — it does not loop forever against a permanently rejected
payload, because a poison record would otherwise consume the retry window
indefinitely.

## Alternatives Considered

- **Fail and log to the debug log.** Rejected: debug logs expire, are not
  queryable, and nobody is watching them.
- **Retry inside the same Queueable by re-enqueueing.** Rejected: a failing
  callout re-enqueued immediately fails again, and chained Queueables have their
  own depth limits. A scheduled retry puts real time between attempts, which is
  what a transient outage needs.
- **Platform Event with a subscriber that retries.** Workable, and heavier: it
  adds an event definition and a subscriber to obtain retry semantics that a
  scheduler already provides.
- **Alert a human on first failure.** Rejected as the *first* response: most
  failures are transient, and an alert per blip trains people to ignore alerts.
  The dashboard makes a persistent failure visible without paging anyone.

## Consequences

- Transient failures resolve without intervention; persistent ones are visible
  rather than silent.
- The log grows and will eventually want a retention policy — a known deferred
  item.
- Testing is done with `HttpCalloutMock` (ADR-013), so failure paths are
  exercised deterministically rather than by hoping a real endpoint misbehaves.
- The audit trail answers "what happened to this loan" from records, not from a
  developer reconstructing it.

## References

- `force-app/main/default/classes/services/LoanSyncService.cls`
- `force-app/main/default/classes/services/LoanSyncRetryScheduler.cls`
- `force-app/main/default/objects/Loan_Sync_Log__c/`
- `force-app/main/default/lwc/loanSyncDashboard/`
