# Contributing

This is a personal portfolio project rather than an open-source product, so
there is no roadmap to volunteer for. Corrections are welcome all the same —
particularly anything that would be wrong or unsafe if copied into a real org.

## What is most useful

- **A mistake in the code.** A missed bulkification path, a sharing declaration
  that should not be there, a query outside `selectors/`, a test that asserts
  nothing.
- **A mistake in the reasoning.** The fourteen records in [`docs/adr/`](docs/adr/)
  state why each decision was made. If a premise is wrong, the decision is
  wrong — and that is worth more than a patch.
- **A platform change.** These files were written against API 62–66. If a newer
  release makes an approach here obsolete — Lightning Web Security relaxing
  enough to drop the Visualforce bridge in
  [ADR-004](docs/adr/ADR-004-visualforce-bridge-for-maps-sdk.md), for instance —
  saying so is a real contribution.

## Working locally

```bash
git clone https://github.com/aksumustafa1625/urla-shoes.git
cd urla-shoes
sf org login web --alias urla --set-default
sf project deploy start --source-dir force-app --test-level RunLocalTests
```

Then configure the API keys — the project deploys and runs without them, but the
map and weather surfaces will report that they are missing
([ADR-014](docs/adr/ADR-014-graceful-degradation-on-ai-and-key-absence.md)):

```
Setup → Custom Settings → API Config → Manage → New (Default Organization Level Value)
```

Per-feature post-deploy steps are in the README.

## House rules for code

- **One trigger per object**, routed through `TriggerHandler`. No logic in the
  trigger body — [ADR-001](docs/adr/ADR-001-kevin-ohara-triggerhandler.md).
- **Classes live in the folder that matches their role** — `handlers/`,
  `services/`, `engines/`, `selectors/`, `controller/`, `factories/`, `utils/`.
  [ADR-002](docs/adr/ADR-002-layered-apex-folders.md).
- **SOQL belongs in `selectors/`.** A query written anywhere else should be
  visible in the diff and should be questioned.
- **Every production class ships with a test class.** Coverage was deliberately
  raised from 51% to 92% in one pass; do not walk it back.
- **Bulk-safe by default.** No SOQL or DML inside a loop; assume 200 records.
- **Declare sharing explicitly** on every class, and enforce FLS with
  `USER_MODE` on anything user-facing.
- **No secrets in source, ever.** Read
  [ADR-003](docs/adr/ADR-003-api-keys-in-hierarchy-custom-setting.md) before
  adding an integration.

## Commits

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `security:`, `test:`).
Say what changed and why; the diff already says how.

## If you change a decision

Changing an approach documented in an ADR means updating that ADR — either by
amending it or by adding a record that supersedes it. An ADR that no longer
matches the code is worse than no ADR at all.
