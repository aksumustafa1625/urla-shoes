# Security

## Scope

This is a **portfolio and demonstration project** for a fictional company. It is
not deployed to production and holds no real customer or partner data. Every
Contact, Opportunity, Loan, Lead and Reseller record in `scripts/` and in the
test classes is fabricated, and demo addresses use domains reserved for
documentation (RFC 2606).

## Credentials

**No API key, token or password exists in this repository — in the working tree
or in the git history.**

That was not always true. Two keys were originally written as string literals in
the components that used them, and were later moved into the `API_Config__c`
hierarchical custom setting. The history has since been rewritten to remove
them, and **both keys were rotated**. The decision and the mistake behind it are
recorded in [ADR-003](docs/adr/ADR-003-api-keys-in-hierarchy-custom-setting.md).

Keys are supplied per org after deployment:

```
Setup → Custom Settings → API Config → Manage → New (Default Organization Level Value)
```

The Google Maps key necessarily reaches the browser, because the Maps JavaScript
SDK runs client-side. The control that matters there is an HTTP-referrer
restriction in the Google Cloud console — an org-configuration step, not a code
one.

## Platform security posture

- **Record access.** `File_Hub_Entry__c` has a Private org-wide default; access
  is granted by Apex-managed share records when a file is sent, so it holds in
  reports, the API and Data Loader — not only in the component that respects it
  ([ADR-007](docs/adr/ADR-007-private-sharing-with-apex-managed-shares.md)).
- **Object and field access.** File Hub reads run under `AccessLevel.USER_MODE`
  or `WITH USER_MODE`; writes use `insert as user`. Tests assign the permission
  set to their run-as users, so enforcement is verified rather than asserted
  ([ADR-008](docs/adr/ADR-008-user-mode-enforcement.md)).
- **Sharing declarations.** Every class declares sharing explicitly. The one
  `without sharing` bypass is a single narrow method and is documented as such.
- **AI boundary.** Document classification runs through the Einstein Trust
  Layer, so data stays inside the Salesforce trust boundary with masking,
  zero-retention and audit — relevant for DSGVO in the DACH market.
- **Callouts.** External calls run in Queueables and are tested against
  committed `HttpCalloutMock` implementations, so no test performs a live
  callout ([ADR-013](docs/adr/ADR-013-queueable-callout-with-mock.md)).

## Reporting a problem

If you find a security-relevant mistake — including a pattern that would be
unsafe if copied into a real org — please open an issue, or contact the author
via https://mustafaaksu.dev. There is no bug bounty; corrections are genuinely
welcome.
