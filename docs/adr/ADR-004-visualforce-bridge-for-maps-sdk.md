# ADR-004: The Google Maps SDK is hosted in a Visualforce page, not in the LWC

## Status

**Accepted**

## Date

2026-05-13

## Author

Mustafa Aksu

## Context

The route planner needs the Google Maps JavaScript SDK: an interactive map,
draggable waypoints, and the Directions service. The natural home is the
`routeWeather` Lightning Web Component that orchestrates the feature.

**Lightning Web Security** prevents that. Third-party scripts loaded into an LWC
run in a sandboxed environment where the Maps SDK's use of global objects and
DOM manipulation does not behave as the library expects. This is a platform
boundary, not a bug to work around in the component.

## Decision

Host the SDK in a **Visualforce page**, `RouteMapPage`, and embed that page in
the LWC through an iframe. The page is deliberately bare — `showHeader="false"`,
`standardStylesheets="false"`, `applyBodyTag="false"` — so nothing of the
Salesforce chrome interferes with the map canvas.

The page uses `ApiKeyService` as its controller, so the Maps key arrives through
the same mechanism the LWC uses (ADR-003) rather than through a second path.

The LWC keeps orchestration: it collects the route, samples weather at
waypoints, calls Einstein for the safety verdict, and renders the result. Only
the map surface lives behind the bridge.

## Alternatives Considered

- **Load the SDK directly in the LWC via `loadScript`.** Rejected: Lightning Web
  Security is the blocker, and the failure mode is subtle breakage rather than a
  clean error.
- **A different mapping library that is LWS-compatible.** A reasonable path, and
  the right one if the Maps SDK were incidental. Rejected because the Directions
  service is the feature, not the map tiles.
- **`lightning-map`, the standard component.** Rejected: it renders markers but
  offers no route calculation, which is the entire point of the feature.
- **Server-side route calculation in Apex.** Rejected: it moves an interactive,
  drag-to-adjust experience onto the server for no gain.

## Consequences

- One Visualforce page persists in an otherwise LWC-only UI layer, and the
  README labels it exactly that way — an "LWS escape hatch".
- Communication across the iframe boundary is explicit message passing rather
  than property binding, which is the cost of the bridge.
- The pattern is reusable: any third-party library that LWS rejects can be
  hosted the same way.
- If Salesforce relaxes LWS for this class of library, the bridge can be removed
  without touching the orchestration logic.

## References

- `force-app/main/default/pages/RouteMapPage.page`
- `force-app/main/default/lwc/routeWeather/`
- README "Architecture overview" — Visualforce Bridge
