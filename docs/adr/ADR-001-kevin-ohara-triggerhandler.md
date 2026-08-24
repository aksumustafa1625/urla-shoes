# ADR-001: One trigger per object, routed through the Kevin O'Hara handler framework

## Status

**Accepted**

## Date

2026-04-18 (established with the first trigger; recorded retrospectively)

## Author

Mustafa Aksu

## Context

Six objects in this project carry trigger logic: Contact (nationalisation),
Opportunity (reseller matching and loan creation), Lead (shift assignment), Task
(aggregation) and ContentDocument (orphan cleanup). Several of them write to
records that other triggers also touch, which is the shape that produces
recursion.

Inline trigger logic does not survive that. Context routing, recursion control
and bypass end up as ad-hoc conditionals repeated per object, and none of the
business logic can be unit-tested without DML.

## Decision

Vendor **Kevin O'Hara's `sfdc-trigger-framework`** and apply a four-layer split
across every automated object:

- **Trigger** — one per object, routing only. Constructs the handler, calls `.run()`.
- **Handler** (`classes/handlers/`) — dispatches trigger contexts, nothing else.
- **Service / Engine** (`classes/services/`, `classes/engines/`) — the business logic.
- **Selector** (`classes/selectors/`) — the SOQL boundary.

The framework is committed into the repository rather than installed, so its
version is pinned and its own tests run with the project's.

## Alternatives Considered

- **Logic in the trigger body.** Rejected: untestable without DML, and recursion
  control would be hand-rolled six times.
- **A hand-written handler base class.** Rejected: it would reimplement
  recursion control, the bypass API and max-loop protection that this framework
  already ships with tests.
- **Flow for the simpler objects.** Rejected for consistency — a codebase where
  half the automation is declarative and half is Apex is harder to reason about
  than one that picks a lane.

## Consequences

- Services and engines take collections and return results, so their tests
  assert on logic directly without inserting records.
- `TriggerHandler.bypass()` is available for data loads and for tests that need
  fixtures without firing automation.
- The framework's own test class inflates the raw test count; the README states
  the split rather than leaving it to be inferred.
- The same layout is used in the sibling `urlashoes-sandbox` and
  `VoltStreamMobility` projects, so the three are structurally comparable.

## References

- [`sfdc-trigger-framework`](https://github.com/kevinohara80/sfdc-trigger-framework)
- `force-app/main/default/classes/TriggerHandler.cls`
- `force-app/main/default/classes/handlers/`
