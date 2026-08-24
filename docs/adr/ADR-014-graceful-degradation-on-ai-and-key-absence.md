# ADR-014: When AI or a key is unavailable, the feature degrades instead of failing

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

Three surfaces in this project depend on something that may simply not be there:
the Einstein Trust Layer for document classification and route-safety analysis,
and the API keys for Maps and OpenWeather.

All three are absent in predictable, non-exceptional situations — a fresh org
where the keys have not been configured yet, an org without Einstein enabled, a
trial that has exhausted its allocation. None of these are bugs, and none should
present as one.

The default outcome is an unhandled exception, which a user reads as "this
application is broken" rather than "this org has not been set up".

## Decision

Every dependency of this kind returns a **usable degraded state**:

- Missing API key → `ApiKeyService` returns an empty string. The map renders an
  inline message; the weather call reports a clear reason.
- Einstein unavailable or failing → `DocumentIntelligenceService` returns a
  friendly message. The document still uploads, still files, still counts for
  compliance; only the automatic categorisation is absent, and the user can set
  the category by hand.

The rule: **the AI layer is an accelerator, never a dependency of the core
transaction.** Nothing a user was doing fails because a model did not answer.

## Alternatives Considered

- **Throw and let the error surface.** Rejected: an unconfigured org is not an
  exceptional condition, and an exception teaches the user nothing about the
  fix.
- **Hide the feature when the dependency is missing.** Rejected: a component
  that vanishes is harder to diagnose than one that explains itself.
- **Block the upload until classification succeeds.** Rejected outright — it
  would make filing a compliance document contingent on a model being available,
  which inverts the priority between the two.

## Consequences

- The project deploys to any org and does something sensible before
  configuration, which makes it reviewable by someone who just cloned it.
- Failure messages point at the setup step rather than at a stack trace.
- Degraded paths are code that must itself be tested, and they are.
- A silent degradation could mask a real outage, so the message is always
  visible in the UI rather than only in a log.

## References

- `force-app/main/default/classes/services/ApiKeyService.cls` — header comment
- `force-app/main/default/classes/services/DocumentIntelligenceService.cls`
- `FILE-HUB.md` §10 "Graceful degradation"
