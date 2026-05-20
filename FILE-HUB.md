# File Hub & Partner Compliance Cockpit

A custom partner document-management platform built on top of Salesforce's native
ContentDocument layer. It evolved through three stages: a semantic file hub, a
compliance scoring cockpit, and an autonomous AI document-compliance loop.

> Org alias: `Urla Shoes` (Developer Edition). API v62.0.

---

## 1. What it is & the problem it solves

Salesforce's native file layer (ContentDocument/ContentVersion) stores file *bytes*
but carries no business meaning — no sender, recipient, category, related record,
read state, or expiry. File Hub adds a **semantic layer** on top and turns it into an
intelligent partner document system in three stages:

- **Base layer** — a file center with sender/recipient/category/related-record
  semantics (Inbox / Sent / My Files).
- **Compliance layer** — tracks the documents every reseller must have on file
  (contract, tax, insurance, bank) and produces a compliance score + network matrix.
- **Autonomous AI layer** — Einstein reads & classifies uploads, missing documents
  are auto-requested from the partner, and requests close themselves once a matching,
  AI-validated file is uploaded.

---

## 2. Architecture

```
LWC PRESENTATION
  fileHub · fileHubSendModal · fileHubUserLookup · fileHubRecordLookup
  complianceCockpit · resellerComplianceChecklist · documentAiClassifier · documentRequests
        │ @AuraEnabled                 ▲ Lightning Message Service (Compliance_Update)
        ▼                              │
APEX BUSINESS LOGIC
  FileHubController (with sharing) · FileHubSharingHelper (without sharing)
  ComplianceService · DocumentIntelligenceService · ComplianceRequestService
        │ DML/SOQL (WITH USER_MODE)    │ ConnectApi.EinsteinLLM
        ▼                              ▼
DATA + AI
  File_Hub_Entry__c · Compliance_Requirement__mdt · Document_Request__c
  DocumentClassification (GenAiPromptTemplate, GPT-4o mini)
        │ pointer (ContentDocument_Id__c)
        ▼
NATIVE FILE LAYER
  ContentVersion · ContentDocument · ContentDocumentLink
```

---

## 3. Data model

### `File_Hub_Entry__c` (sharing model: **Private** → Apex-managed shares)
| Field | Type | Purpose |
|---|---|---|
| Sender__c | User lookup | Uploader |
| Recipient__c | User lookup | Recipient (null = personal) |
| Category__c | Picklist (required) | Contract / Tax Document / Insurance / Bank Details / Catalog / Compliance / Marketing / Personal / Other |
| Related_Reseller__c | Lookup → Reseller__c | Compliance key |
| Related_Loan__c | Lookup → Loan__c | Loan context |
| Message__c | Long text 2000 | Sender note |
| Read__c | Checkbox | Read flag |
| ContentDocument_Id__c | Text 18 (required) | Pointer to native file |
| Sent_Date__c | DateTime | Set when recipient set |
| File_Name__c / File_Extension__c | Text | Denormalised |
| Expiry_Date__c | Date | Drives compliance expiry |

### `Compliance_Requirement__mdt` (admin-managed, no deploy)
4 records: Signed Contract, Tax Certificate, Insurance, Bank Details.
Fields: Document_Category__c, Requirement_Label__c, Has_Expiry__c, Warning_Days__c,
Sort_Order__c, Active__c.

### `Document_Request__c` (autonomous loop tracking)
Reseller__c, Document_Category__c, Requirement_Label__c, Status__c
(Requested/Fulfilled/Cancelled), Requested_Date__c, Fulfilled_Date__c,
Fulfilled_Entry__c, Message__c, Reason__c. Name = auto-number `REQ-{0000}`.

---

## 4. Apex layer

| Class | Sharing | Responsibility |
|---|---|---|
| `FileHubController` | with sharing | All CRUD + cacheable read + search (getMyFiles, getInbox, getSent, getFilesForRecord, getUnreadCount, getCategoryCounts, getRecentActivity, getMonthActivity, searchUsers/Resellers/Loans, createEntry, markAsRead, deleteEntry) |
| `FileHubSharingHelper` | without sharing | Narrow bypass so a recipient (Read-only share) can flip their own Read__c |
| `ComplianceService` | with sharing | Per-(reseller × requirement) status MISSING/EXPIRED/EXPIRING/OK + score; getMatrix / getResellerCompliance / getRequirements; WITH USER_MODE |
| `DocumentIntelligenceService` | with sharing | classifyAndApply: Einstein classify → validate → apply category/expiry → autoFulfill matching request; @TestVisible mock hook |
| `ComplianceRequestService` | with sharing | requestAllGaps (sweep) / requestDocument / autoFulfill / getRequests; best-effort email to primary contact |

### Compliance scoring rules
- **MISSING** (gray) — no file in that category for the reseller
- **EXPIRED** (red) — Expiry_Date__c in the past
- **EXPIRING** (amber) — expires within Warning_Days
- **OK** (green) — present and valid
- **Score** = (OK + EXPIRING) / total × 100 — EXPIRING is still valid today but flagged.

---

## 5. LWC layer

**Base:** `fileHub` (3 tabs, colored category tiles, month-based GitHub-green heatmap,
category-coded row stripes, recent activity), `fileHubSendModal`, two custom lookups
(show top 10 on focus).

**Compliance:**
- `complianceCockpit` — network matrix (rows = resellers, columns = requirements,
  cells = colored status dots) + 5 summary stat cards + score bars. Home/App page.
- `resellerComplianceChecklist` — conic-gradient score ring + checklist. **Subscribes
  to LMS** → score re-computes live when AI fulfills.
- `documentAiClassifier` — lists a reseller's files, "✨ Analyze with AI" → toast +
  inline result; **publishes LMS** on apply.
- `documentRequests` — request list + "Request Missing Documents" sweep; subscribes to LMS.

**Connector:** `Compliance_Update` Lightning Message Channel broadcasts compliance
changes so components refresh live (no polling).

---

## 6. End-to-end flows

### Send a file
Modal → `lightning-file-upload` creates ContentVersion/Document → `createEntry` builds
File_Hub_Entry__c + Apex-managed Read share for recipient + ContentDocumentLinks →
appears in recipient's Inbox, badge increments.

### Mark as read
Recipient opens file → `markAsRead` → `FileHubSharingHelper` (without sharing) sets
Read__c=true (Read-only share can't otherwise update).

### Compliance scoring
Cockpit → `getMatrix()` evaluates all resellers × requirements in one bulk SOQL → matrix
+ scores. Record page → `getResellerCompliance(recordId)` → ring + checklist.

### AI classification
"✨ Analyze with AI" → `classifyAndApply` → Einstein returns JSON → category + expiry
applied → toast `Classified as Tax Document (92%) · valid until 2027-03-01`.

### 🔄 Autonomous loop (the centerpiece)
```
1. Cockpit: Reseller B is missing Bank Details (red)
2. "Request Missing Documents" → Document_Request__c (Requested) + email to primary contact
3. Partner uploads the file in File Hub
4. "Analyze with AI" → Einstein says "Bank Details" → applied
   → autoFulfill: matching request flips to "Fulfilled"
5. LMS broadcast → checklist score + request list update live
```
A closed "detect → request → AI-validate → self-update" loop.

---

## 7. Security model
- **Private object + Apex-managed sharing** — recipients see only files sent to them.
- **with/without sharing split** — main controller honours sharing; only the read-flag
  uses a narrow bypass.
- **WITH USER_MODE** — compliance queries enforce the running user's FLS/CRUD.
- **Einstein Trust Layer** — AI call passes through masking + zero-retention + audit;
  data stays inside the Salesforce trust boundary (DSGVO-relevant for the DACH market).

---

## 8. AI integration detail
- Prompt Template `DocumentClassification` (`GenAiPromptTemplate`, type `einstein_gpt__flex`,
  input `documentContext` primitive://String, model `sfdc_ai__DefaultOpenAIGPT4OmniMini`)
  is authored **as metadata** (not only in Prompt Builder) — version-controlled & deployable.
- `DocumentIntelligenceService` calls `ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate`,
  parses `generations[0].text` as JSON (tolerating ```` ```json ```` fences), validates the
  category, applies it, and closes any matching request.
- **Multimodal upgrade path:** when the org enables multimodal templates, the same template
  can accept the file itself (Prompt Template Attachment) so the LLM reads the PDF directly —
  no Apex change.

---

## 9. Test coverage
| Class | Tests | Coverage |
|---|---|---|
| FileHubController | 21 | ~91% |
| ComplianceService | 7 | 96% |
| DocumentIntelligenceService | 8 | 83% (remainder = live LLM block) |
| ComplianceRequestService | 7 | 97% |

AI tests inject `@TestVisible mockLlmText` so they never make a live callout.

---

## 10. Key design decisions
- **CMT-driven requirements** — admin manages without deploy.
- **LMS live sync** — instant cross-component score updates, no polling.
- **Prompt Template as metadata** — code-versioned, not UI-only.
- **Bulk-safe SOQL** — whole network in one query, governor-safe.
- **Graceful degradation** — if Einstein is unavailable, returns a friendly message
  instead of failing.

---

## 11. Manual setup (Lightning App Builder)
- **Home / App page:** add `Partner Compliance Cockpit`.
- **Reseller record page:** add `Reseller Compliance Checklist` + `AI Document Classifier`
  + `Document Requests`.
- (Also add `File Hub` to Home / Reseller / Loan pages for the base experience.)
- Permission set `File_Hub_User` grants object/field access + Apex class access for all
  five service/controller classes.

---

## 12. Deploy gotchas hit during the build (war stories)
1. CMT records throw `UNKNOWN_EXCEPTION` unless `xmlns:xsd` is declared on the root.
2. `list`, `json`, `end` are reserved Apex identifiers (`json` collides with the `JSON`
   class — Apex is case-insensitive).
3. PermissionSet `objectPermissions` blocks must be contiguous.
4. `Reseller__c.Tier__c` is a read-only formula — never set it in test data.
5. Required fields can't have explicit `fieldPermissions` in a permission set (auto-granted).
6. Sharing model must be `Private` for Apex Read shares to be non-trivial.
