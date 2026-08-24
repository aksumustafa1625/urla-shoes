# ADR-005: The Einstein Prompt Template is authored as metadata, not only in Prompt Builder

## Status

**Accepted**

## Date

2026-05-20

## Author

Mustafa Aksu

## Context

The Partner Compliance Cockpit classifies each uploaded document into a category
and extracts its expiry date. The classification runs through an Einstein Prompt
Template on `sfdc_ai__DefaultOpenAIGPT4OmniMini`, called from Apex via
`ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`.

Prompt Builder is a UI. A template authored there lives in the org and nowhere
else: it is not in source control, not in a diff, not deployable to a second org
without clicking through the same screens, and not revertible when a change
makes classification worse.

For a component whose output drives an automated decision — closing a document
request — that is the same as having untracked business logic.

## Decision

Author the template as a **`GenAiPromptTemplate` metadata file** in the
repository:

- type `einstein_gpt__flex`
- input `documentContext`, `primitive://String`
- model `sfdc_ai__DefaultOpenAIGPT4OmniMini`

It deploys with the rest of the project, changes appear in diffs, and a
regression can be reverted with `git revert` rather than by remembering what the
prompt used to say.

`DocumentIntelligenceService` parses `generations[0].text` as JSON, tolerating
the fenced ```` ```json ```` wrapper that the model sometimes emits, validates
the returned category against the known set, and only then applies it.

## Alternatives Considered

- **Author in Prompt Builder only.** Rejected: the prompt is business logic, and
  business logic that is not in source control cannot be reviewed or reverted.
- **Build the prompt string in Apex.** Rejected: it works, but it gives up the
  Trust Layer's template handling — masking, grounding and audit — and puts
  prompt text inside a class where a reviewer would not look for it.
- **Trust the model's output shape.** Rejected: the JSON-fence tolerance and the
  category validation exist because the raw output is not reliably clean.

## Consequences

- Prompt changes are reviewable and revertible like any other change.
- The template deploys to a fresh org with the project, so the feature works
  after `sf project deploy start` without a manual authoring step.
- Editing the template in Prompt Builder now creates drift between org and
  repository — the standard cost of source-controlling anything that also has a
  UI.
- A **multimodal upgrade path** stays open: when the org enables multimodal
  templates, the same template can accept the file itself as a Prompt Template
  Attachment and read the PDF directly, with no Apex change.

## References

- `force-app/main/default/genAiPromptTemplates/`
- `force-app/main/default/classes/services/DocumentIntelligenceService.cls`
- `FILE-HUB.md` §8 "AI integration detail"
