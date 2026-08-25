# Urla Shoes — Salesforce DX Reference Project

A multi-feature Salesforce reference implementation for a fictitious shoe-distribution company. Designed to demonstrate production-shaped patterns across LWC, Apex, async integration, real-time dashboards, Einstein AI, and document management.

> **How this was built.**
>
> I used Claude to build this repository, the way an engineer today uses an IDE — I would rather say it first than have it asked. The model wrote code; I set the structure, and every decision went through me.
>
> So the question worth asking is not *whether* AI wrote it, but **who decided and who verified.** That record is in [`docs/adr/`](docs/adr/): **14 architecture decision records**, each naming the constraint, the choice, the alternatives rejected, and what rejecting them cost. A model does not turn down three options and price the fourth.
>
> **What this is not:** a demonstration, not a production system with real users. Built alone, so no colleague reviewed it. Every number is mine — please run them yourself.

## Features

| # | Feature | Stack | Description |
|---|---------|-------|-------------|
| 1 | **Route & Weather Navigator** | LWC + VF bridge + Apex + Einstein | Google Maps route planner with 5-waypoint OpenWeather sampling and a GPT-4o mini safety verdict via the Einstein Trust Layer. |
| 2 | **Loan Creation Pipeline** | Apex Trigger + Queueable + Scheduler + LWC | Auto-creates a Loan record on Closed-Won Opportunity, syncs to a core system via async callout, retries failures, audits every attempt, and surfaces state in an admin LWC dashboard. |
| 3 | **Contact Nationalization** | Apex Queueable + HttpCalloutMock | Reference implementation showing the canonical pattern for trigger → Queueable → external API enrichment, fully test-covered. |
| 4 | **Reseller Matching Engine** | Apex Trigger + Selector + Service | Resolves Opportunity → Reseller via email then domain fallback, with diagnostic logging for unmatched cases and a magic-link partner-registration email. |
| 5 | **Lead Queue + Shift Dashboard** | LWC + Platform Events + Schedulable | Round-robin lead assignment across shift-bound reps with SLA expiry, real-time dashboard via push + poll, and timezone-aware scheduling. |
| 6 | **Reseller Tier Badge** | LWC + uiRecordApi | Roadmap visualisation of Bronze → Silver → Gold → Platinum partner tiers with progress to next tier. |
| 7 | **Partner Document Center (File Hub)** | LWC + Apex + ContentDocument | Modern document-management surface over Salesforce Files — categorize, send, receive, and link files to Reseller / Loan records. See [FILE-HUB.md](FILE-HUB.md). |
| 8 | **Opportunity Task Score** | Apex Trigger + AggregateResult | Auto-maintained `Score__c` and `completed_task__c` on Opportunity from related Tasks. |
| 9 | **Partner Compliance Cockpit + AI Document Classifier** | LWC + Custom Metadata + Einstein + LMS | Network-wide compliance matrix with per-partner scores; an Einstein Prompt Template (GPT-4o mini) classifies each uploaded document into structured JSON, extracts expiry, and auto-closes the matching `Document_Request__c`. File Hub categories feed a live checklist that re-scores via Lightning Message Service. See [FILE-HUB.md](FILE-HUB.md). |

## Architecture overview

```
LWC Layer
 ├── routeWeather              (Maps + Weather + Einstein orchestrator)
 ├── loanSyncDashboard         (Loan retry + audit dashboard)
 ├── leadShiftDashboard        (Real-time shift + queue dashboard)
 ├── resellerTierBadge         (Partner tier visualisation)
 ├── fileHub                   (Document management — home + record page)
 ├── fileHubSendModal          (Send-to-user modal)
 ├── fileHubUserLookup         (Reusable user picker)
 └── urlaShoesHeader           (Branded app header)

Visualforce Bridge
 └── RouteMapPage              (Google Maps SDK host — LWS escape hatch)

Apex Layer
 ├── handlers/                 (Trigger handlers — Kevin O'Hara pattern)
 ├── services/                 (Business logic — Loan, Lead, Reseller, Nationalize)
 ├── engines/                  (Stateful algorithms — round robin, matching)
 ├── selectors/                (SOQL boundary — Shift, Reseller Mapping)
 ├── controller/               (LWC-facing Aura entrypoints)
 ├── factories/                (Test data + HttpCalloutMock)
 ├── tests/                    (Apex test classes)
 └── utils/                    (Pure helpers — EmailUtils)

Custom Objects
 ├── Loan__c                   (Closed-Won pipeline output)
 ├── Loan_Sync_Log__c          (Per-attempt audit trail)
 ├── File_Hub_Entry__c         (File metadata wrapper)
 ├── API_Config__c             (Hierarchical custom setting for keys)
 └── Lead_Shift_Event__e       (Platform Event for real-time dashboard)

Einstein
 └── RouteWeatherAnalysis      (Prompt Template via Einstein Trust Layer)
```

## Prerequisites

- Salesforce CLI (`sf` 2.0+)
- VS Code with Salesforce Extension Pack
- A Developer Edition org or Scratch Org with:
  - State & Country Picklists enabled
  - Einstein Generative AI enabled (for Route Weather Navigator)

## Setup

```bash
# Clone + authorize
git clone <repository-url>
cd "Urla Shoes"
sf org login web --alias urla-shoes

# Deploy
sf project deploy start --target-org urla-shoes

# Run all tests
sf apex run test --target-org urla-shoes --result-format human --code-coverage
```

### Per-feature post-deploy

| Feature | Post-deploy step |
|---------|------------------|
| Route Weather Navigator | Setup → Custom Settings → API Config → Manage → set Google Maps + OpenWeather keys |
| Route Weather Navigator | Setup → Einstein → Prompt Builder → activate `RouteWeatherAnalysis` template |
| Loan Pipeline | Anonymous Apex: `System.schedule('Loan Sync Retry', '0 0,15,30,45 * * * ?', new LoanSyncRetryScheduler());` |
| Lead Queue | Anonymous Apex: `LeadQueueScheduler.startScheduler();` |
| File Hub | Assign `File_Hub_User` permission set + drop the `fileHub` LWC into Home, Reseller, Loan pages via Lightning App Builder |

## Test coverage

```bash
sf apex run test \
  --target-org urla-shoes \
  --code-coverage \
  --result-format human
```

Specific test classes:
- `NationalizeServiceTest` — 6 scenarios covering external API integration
- `OpportunityLoanTriggerHandlerTest` — 9 scenarios covering Closed-Won → Loan → Sync flow
- `FileHubControllerTest` — 12 scenarios covering send / receive / share / delete
- `TriggerHandler_Test` — base class smoke tests

## Decisions

Fourteen architecture decision records live in [`docs/adr/`](docs/adr/). Each one
states the constraint that ruled out the obvious answer — Lightning Web Security
blocking the Maps SDK inside an LWC, `with sharing` not enforcing field access,
streaming silence being indistinguishable from no news — then what was chosen and
what it costs.

Start with [the index](docs/adr/README.md); it flags the two pairs worth reading
against each other.

## Deep dives

| Document | Topic |
|----------|-------|
| [FILE-HUB.md](FILE-HUB.md) | Partner Document Center architecture and post-deploy setup |

## Recent updates

**2026-07-02**
- **File Hub category taxonomy unified with the AI/compliance categories.** The tile bar, filter dropdown, and `getCategoryCounts`/`buildEmptyCategoryMap` now include **Tax Document**, **Insurance**, and **Bank Details**, so a document the AI classifier files as e.g. *Insurance* lands under its own filter tile instead of being uncounted. Tile grid is now a 5-column, two-row layout (10 tiles).
- **`essenWeather` LWC** now loads its OpenWeather key from `API_Config__c` via `ApiKeyService` (same pattern as `routeWeather`) — no key in the component bundle.
- **API-key setup** — `scripts/apex/setApiKeys.example.apex` (committed template) upserts the Google Maps + OpenWeather keys into `API_Config__c`; the real-key copy `scripts/apex/setApiKeys.apex` is **gitignored**, so no secret ever reaches source.
- **`demo-files/`** (gitignored) — corporate demo PDFs (distribution agreement, tax certificate, insurance, bank details, catalog, compliance declaration) for the File Hub / Partner Compliance demos.

## License

Educational / portfolio use. External API keys must be your own.
