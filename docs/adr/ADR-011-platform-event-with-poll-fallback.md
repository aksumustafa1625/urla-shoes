# ADR-011: The shift dashboard uses a Platform Event for push, and keeps a poll as the floor

## Status

**Accepted**

## Date

2026-04-19

## Author

Mustafa Aksu

## Context

The lead-shift dashboard shows which representative is on shift and how the
round-robin queue is distributing incoming leads. Assignment happens server-side
in a trigger; the dashboard is a separate browser session belonging to a
supervisor who may have had the page open for hours.

There is no relationship between the two. The supervisor's page has no way to
know that a lead was just assigned unless the server tells it.

## Decision

Publish a **Platform Event**, `Lead_Shift_Event__e`, when an assignment happens.
The dashboard subscribes over the empApi streaming channel and updates on
arrival.

**And keep a low-frequency poll underneath it.** Streaming is not a guarantee:
a dropped connection, a browser tab suspended by the OS, or an event published
outside the subscription window all produce a dashboard that is silently stale.
Silence is indistinguishable from "nothing happened".

Push is the fast path. The poll is the floor that makes staleness bounded rather
than unbounded.

## Alternatives Considered

- **Polling only.** Rejected as the sole mechanism: the interval that feels
  "real-time" is the interval that is most wasteful, since most ticks find no
  change.
- **Platform Event only.** Rejected: it is the right primitive but the wrong
  guarantee. A supervisor watching a dashboard that quietly stopped receiving
  events is worse off than one watching a dashboard that updates slowly.
- **`refreshApex` triggered by a user action.** Rejected: it requires the user
  to suspect the data is stale, which is precisely what they cannot know.
- **Change Data Capture on Lead.** Rejected: CDC reports field-level changes on
  the record, while the dashboard's unit of interest is the assignment event —
  a business fact that the trigger already knows and can describe directly.

## Consequences

- The common case is instant and cheap.
- The failure case degrades to "late" rather than "wrong", which is the
  distinction that matters for a monitoring surface.
- Two update paths exist, so the render must be idempotent — applying the same
  assignment twice cannot double-count.
- Platform Events are subject to daily delivery allocations, which is a real
  constraint to watch if assignment volume grows.

## References

- `force-app/main/default/objects/Lead_Shift_Event__e/`
- `force-app/main/default/classes/handlers/LeadShiftTriggerHandler.cls`
- `force-app/main/default/lwc/leadShiftDashboard/`
- README — "real-time dashboard via push + poll"
