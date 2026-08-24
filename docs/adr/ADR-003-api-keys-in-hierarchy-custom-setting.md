# ADR-003: API keys live in a hierarchical custom setting, never in source

## Status

**Accepted**

## Date

2026-06-30 (the fix); superseding the original approach of 2026-04-18

## Author

Mustafa Aksu

## Context

Two features call external services that need keys: the route planner uses the
Google Maps JavaScript SDK, and the weather sampler uses OpenWeather.

**This project got it wrong first.** Both keys were written as string literals
in the components that used them — the Maps key in the Visualforce page, the
OpenWeather key in `essenWeather.js`. That is the shortest path to a working
demo and it is exactly how keys end up in git history, where deleting the line
does not delete the secret.

Three commits record the correction:
`security: remove hardcoded API keys from source` (2026-06-30),
`security: route essenWeather key through ApiKeyService` (2026-07-02), and
earlier `Move API keys to API_Config__c custom setting` (2026-05-13).

This ADR is written after the fact and states the original mistake deliberately.
An architecture record that only describes the final shape teaches nothing about
why the shape is what it is.

## Decision

Store both keys in `API_Config__c`, a **hierarchical custom setting**, and read
them through a single `ApiKeyService`:

```apex
public String mapsApiKey { get { return readKey('Google_Maps_Api_Key__c'); } }
```

The Visualforce page binds to it as a controller property; the LWC reads it
through an `@AuraEnabled` method. Neither key string exists in the repository,
and a missing key degrades gracefully — the map renders an inline error, the
weather call returns a clear message — rather than throwing.

## Alternatives Considered

- **Named Credential.** The right answer for a server-side callout, and it is
  what a production system should use for OpenWeather. Rejected here because the
  Maps key is consumed by **client-side JavaScript** inside a Visualforce page,
  which a Named Credential cannot supply; splitting the two mechanisms would
  mean two configuration surfaces for one setup step.
- **Protected Custom Metadata Type.** Comparable, and deployable — but custom
  metadata is packaged and moves between orgs, which is the wrong lifecycle for
  a secret that should differ per org.
- **Leaving the keys in source for a demo org.** Rejected on the evidence: the
  original keys had to be rotated because history retains what the working tree
  forgets.

## Consequences

- The repository can be public. Setup is a documented five-step configuration
  in `ApiKeyService`'s own header comment.
- Keys differ per org and per user without a redeploy, which is what the
  hierarchy type is for.
- The Maps key still reaches the browser, because a client-side SDK requires it.
  Restricting it by HTTP referrer in the Google Cloud console is the control
  that matters there, and it is an org-configuration step rather than a code one.
- **Any key committed before this change must be treated as compromised and
  rotated**, regardless of later history rewriting.

## References

- `force-app/main/default/classes/services/ApiKeyService.cls`
- `force-app/main/default/objects/API_Config__c/`
- Commits `security: remove hardcoded API keys from source`, `security: route essenWeather key through ApiKeyService`
