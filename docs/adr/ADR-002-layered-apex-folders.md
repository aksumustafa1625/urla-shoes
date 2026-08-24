# ADR-002: Apex is organised by role — handlers, services, engines, selectors, factories, utils

## Status

**Accepted**

## Date

2026-05-13 (formalised when the class count passed ~30)

## Author

Mustafa Aksu

## Context

This project reached sixty Apex classes across nine features. A flat `classes/`
folder at that size stops communicating anything: a reader cannot tell from a
file list which classes hold business rules, which touch the database, and which
exist only for tests.

The risk is not aesthetic. When SOQL is written wherever it is convenient, the
same query appears in four places with three different field lists, and adding a
field to one of them silently leaves the others stale.

## Decision

Organise `force-app/main/default/classes/` by **role**, with a folder per layer:

| Folder | Holds | Rule |
|---|---|---|
| `handlers/` | Trigger handlers | Dispatch only, no business logic |
| `services/` | Business logic | Stateless, collection-in / collection-out |
| `engines/` | Stateful algorithms | Round-robin cursor, reseller matching |
| `selectors/` | SOQL | The only place a query is written |
| `controller/` | `@AuraEnabled` entry points | Thin; delegates to services |
| `factories/` | Test data, `HttpCalloutMock` | Never referenced by production code |
| `utils/` | Pure helpers | No SOQL, no DML, no state |
| `tests/` | Apex test classes | One per production class |

Salesforce flattens these folders at deploy time, so the structure costs nothing
at runtime and exists purely for the reader.

## Alternatives Considered

- **Flat `classes/` folder.** Rejected at this size — sixty files in one
  directory with no grouping.
- **Folder per feature** (`fileHub/`, `loans/`, `leads/`). Rejected: shared
  classes such as `TriggerHandler`, `EmailUtils` and the selectors have no
  natural home, and cross-feature reuse becomes invisible.
- **Multiple package directories in `sfdx-project.json`.** Rejected as
  disproportionate for a single-org project; the sibling TechnoStore project
  does use a six-package layout, where the scale justifies it.

## Consequences

- The SOQL boundary is enforceable by inspection: a query outside `selectors/`
  is visible in a diff.
- A reader can find the business rule for a feature without opening files at
  random.
- Moving a class between layers is a real refactor with a visible diff, which is
  the intended friction.
- Folder names carry meaning that Salesforce itself does not enforce, so the
  convention has to be documented — which is what this record is for.

## References

- `force-app/main/default/classes/` — the folder layout
- README "Architecture overview"
