# ADR-006: Compliance requirements are Custom Metadata, so an admin changes them without a deploy

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

The Compliance Cockpit scores each partner against a set of required documents —
what must be on file, and which document category satisfies it. That set is not
a technical constant. It changes when a regulation changes, when the business
adds a partner tier, or when a market is added.

Anything that changes on a business timetable but lives in Apex means a developer
and a deployment for what is, in substance, a data edit.

## Decision

Model the requirements as a **Custom Metadata Type**,
`Compliance_Requirement__mdt`. Scoring reads the active records and computes each
partner's score from them; no requirement is named in code.

An administrator adds, retires or reweights a requirement through Setup. No
deployment, no release, no developer.

## Alternatives Considered

- **Constants or a picklist in Apex.** Rejected: the change would need a
  developer and a deploy every time the compliance set moves.
- **A custom object holding requirement records.** Workable, and it would allow
  end users to edit rules. Rejected because custom metadata **deploys with the
  project**, so a fresh org has the requirement set immediately, whereas records
  in a custom object would need a seeding step. Configuration should travel with
  the code; transactional data should not.
- **Custom Settings.** Rejected: they hold values, not a structured, queryable
  set of typed records with relationships.

## Consequences

- The compliance rule set is configuration, editable by the people who own the
  rules.
- The set travels with the project, so deployment produces a working feature.
- Scoring is bulk-safe: the whole partner network is scored in one query rather
  than one query per partner.
- Custom metadata records deploy in XML, and that XML has a sharp edge — a record
  file throws `UNKNOWN_EXCEPTION` unless `xmlns:xsd` is declared on the root
  element. This cost real debugging time and is recorded in `FILE-HUB.md` §12.

## References

- `force-app/main/default/objects/Compliance_Requirement__mdt/`
- `force-app/main/default/customMetadata/`
- `force-app/main/default/classes/services/ComplianceService.cls`
- `FILE-HUB.md` §3, §10, §12
