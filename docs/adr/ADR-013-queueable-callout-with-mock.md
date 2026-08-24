# ADR-013: External enrichment runs in a Queueable and is tested against a committed mock

## Status

**Accepted**

## Date

2026-04-18

## Author

Mustafa Aksu

## Context

Two features call outward from a trigger context: Contact nationalisation
(Nationalize.io) and loan sync. Apex forbids a callout from a trigger, so the
work has to move off the synchronous transaction regardless of preference.

The second problem is testing. A test that performs a real callout is not a
test: it fails when the network fails, when the vendor changes a response, and
in every org where the remote site is not configured. It also cannot exercise
the failure paths that matter most, because a live endpoint refuses to be
unreliable on demand.

## Decision

Run the callout in a **Queueable** enqueued from the handler, and test it
against an **`HttpCalloutMock` committed to the repository**:
`NationalizeCalloutMock`, `LoanSyncCalloutMock`.

The mocks live in `classes/factories/` alongside the test data factory, and they
return the shapes that matter — a good response, a malformed one, an error
status — so the failure branches are covered deterministically.

## Alternatives Considered

- **`@future` methods.** Rejected: no chaining, no state, no `Finalizer`, and
  they cannot be enqueued from a Queueable. Queueable is the strictly more
  capable primitive for the same cost.
- **Batch Apex.** Rejected: the unit of work is one record reacting to one
  event, not a scan over many.
- **Live callouts in tests.** Rejected: non-deterministic, org-dependent, and
  unable to reproduce failures.
- **Mocking with an anonymous inner class per test.** Rejected: the same
  response shapes would be re-declared in every test class. A named mock in
  `factories/` is written once and reused.

## Consequences

- Tests run offline, in any org, with no remote site configuration.
- Failure paths — timeouts, malformed JSON, non-200 responses — are covered,
  which is what makes ADR-012's retry logic testable at all.
- The mocks must be maintained if a real response shape changes; a mock that has
  drifted from reality is a test that passes for the wrong reason. Trading that
  risk for determinism is the deliberate call.
- Callout results arrive asynchronously, so any UI reading them must handle "not
  yet" as a state rather than as an error.

## References

- `force-app/main/default/classes/services/NationalizeService.cls`
- `force-app/main/default/classes/factories/NationalizeCalloutMock.cls`, `LoanSyncCalloutMock.cls`
