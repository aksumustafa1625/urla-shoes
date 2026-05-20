# Urla Shoes — Project Context for Claude

**This is the first file Claude reads in a new session.** It captures everything that exists, the most recent active work, what's deployed, and how to pick up where we left off.

Last updated: **2026-05-13** (session ended with File Hub v5 — GitHub-style monthly heatmap)

---

## 1. What this project is

**Urla Shoes** is a Salesforce DX portfolio project for Mustafa Aksu (CV: mustafaaksu.dev). It's a multi-feature demo built to be **defendable in a tech interview** — every feature has business reasoning, governor-limit awareness, test coverage, and a documented design choice trail.

The fictional company is a Germany-based shoe distributor with a reseller/partner network. Most features tie into that narrative: closing deals → creating loans → reseller matching → partner document management.

**Target audience:** DACH-region Salesforce hiring teams.

---

## 2. Tech stack

- Salesforce DX project, API v62.0 (FileHub) / v66.0 (org default)
- Apex (Queueable, Schedulable, Trigger Handler framework — Kevin O'Hara pattern)
- Lightning Web Components (LWC)
- Visualforce (single use: Google Maps iframe bridge for LWS workaround)
- Salesforce Einstein (Prompt Templates + ConnectApi.EinsteinLLM)
- Native ContentDocument / ContentVersion for file storage
- Platform Events (Lead_Shift_Event__e for real-time dashboard)
- Custom Settings (API_Config__c) — admin-managed config
- Custom Objects: Loan__c, Loan_Sync_Log__c, File_Hub_Entry__c, Lead_Queue__c, Reseller__c, Reseller_Mapping__c, Reseller_Match_Log__c, Shift__c, SLA_Breach_Log__c, plus fields on standard Opportunity/Contact

---

## 3. Connected org

- **Alias:** `Urla Shoes` (note the space — quote it: `--target-org "Urla Shoes"`)
- **Username:** your-org-user@example.com
- **Type:** Developer Edition org (file storage limit: 20 MB, data storage: 5 MB)
- Default username for the project — most commands work without explicit `--target-org`

---

## 4. Features in the project (all deployed)

| # | Feature | Status | Files |
|---|---------|--------|-------|
| 1 | **Route & Weather Navigator** | ✓ Production-shaped | lwc/routeWeather, pages/RouteMapPage, services/RouteWeatherAnalysisService |
| 2 | **Contact Nationalization** | ✓ Reference implementation | services/NationalizeService, handlers/ContactTriggerHandler, factories/NationalizeCalloutMock |
| 3 | **Loan Creation pipeline** | ✓ Production-shaped | services/LoanCreationService, services/LoanSyncService, services/LoanSyncRetryScheduler, lwc/loanSyncDashboard |
| 4 | **Reseller Matching** | ✓ Working | engines/ResellerMatchingEngine, handlers/OpportunityResellerTriggerHandler, services/ResellerMatchLogService, services/ResellerReconciliationService |
| 5 | **Lead Queue + Shift** | ✓ Working | engines/LeadQueueProcessor, services/LeadQueueService, services/LeadQueueScheduler, lwc/leadShiftDashboard |
| 6 | **Reseller Tier Badge** | ✓ Working | lwc/resellerTierBadge |
| 7 | **Task → Opp Score aggregation** | ✓ Working | triggers/TaskTrigger, handlers/TaskTriggerHandler |
| 8 | **File Hub** (Partner Document Center) | ✓ Deployed v5 | lwc/fileHub, lwc/fileHubSendModal, lwc/fileHubUserLookup, lwc/fileHubRecordLookup, classes/controller/FileHubController, classes/controller/FileHubSharingHelper |

---

## 5. Most recent active work — File Hub feature

This is the **last major thing built** and the most likely follow-up area. Documented in detail in [FILE-HUB.md](FILE-HUB.md) at the repo root.

### What it is
Custom file management layer on top of Salesforce's native ContentDocument/ContentVersion. Sender/recipient/category/record-link semantics on top of raw file storage. Renders on the Home page (3 tabs: My Files / Inbox / Sent) and on Reseller / Loan record pages (record-scoped view).

### Architecture
```
LWC layer
 ├── fileHub               (main surface, multi-target)
 ├── fileHubSendModal      (send-to-user modal)
 ├── fileHubUserLookup     (recipient picker, auto-shows top 10 on focus)
 └── fileHubRecordLookup   (generic Reseller/Loan picker via lookup-type prop)

Apex layer
 ├── FileHubController       (with sharing) — all CRUD + read methods
 └── FileHubSharingHelper    (without sharing) — markAsRead bypass for recipient

Custom object
 └── File_Hub_Entry__c       (wraps ContentDocument with business metadata)

Native Salesforce file layer
 ├── ContentVersion        (file bytes)
 ├── ContentDocument       (file identity)
 └── ContentDocumentLink   (sharing — to entry, to recipient, to related record)
```

### Apex method inventory (FileHubController)

| Method | Cacheable | Purpose |
|--------|-----------|---------|
| `getMyFiles(category, searchTerm)` | yes | My Files tab data |
| `getInbox(category, searchTerm)` | yes | Inbox tab data (recipient = me) |
| `getSent(category, searchTerm)` | yes | Sent tab data |
| `getFilesForRecord(recordId)` | yes | Record-page embed (Reseller__c / Loan__c) |
| `getUnreadCount()` | yes | Inbox badge count |
| `getCategoryCounts(viewType, recordId)` | yes | Tile bar counts per category |
| `getRecentActivity()` | yes | Recent Activity panel (last 7 days, top 10) |
| `getMonthActivity()` | yes | Heatmap data (current month days + activity counts + isToday/isFuture flags) |
| `searchUsers(searchTerm)` | yes | Recipient picker (top 10 on blank term) |
| `searchResellers(searchTerm)` | yes | Reseller picker (top 10 on blank term) |
| `searchLoans(searchTerm)` | yes | Loan picker (top 10 by CreatedDate DESC) |
| `createEntry(...)` | no | Send/upload — creates File_Hub_Entry + ContentDocumentLinks + share |
| `markAsRead(entryId)` | no | Delegates to FileHubSharingHelper |
| `deleteEntry(entryId)` | no | Sender-only delete (auth check inside) |

### Data model (File_Hub_Entry__c fields)

- `Sender__c` (User lookup) — uploader
- `Recipient__c` (User lookup, optional) — null = personal upload
- `Category__c` (picklist, required) — Contract / Catalog / Compliance / Marketing / Personal / Other
- `Related_Reseller__c` (lookup to Reseller__c) — optional
- `Related_Loan__c` (lookup to Loan__c) — optional
- `Message__c` (long text 2000) — optional sender note
- `Read__c` (checkbox, default false)
- `ContentDocument_Id__c` (text 18, required) — pointer to native ContentDocument
- `Sent_Date__c` (datetime) — set when Recipient is set
- `File_Name__c` (text 255) — denormalised title
- `File_Extension__c` (text 20) — denormalised lowercase ext for icon mapping
- `Expiry_Date__c` (date) — V2 candidate, field exists but no UI yet

Object sharing model: **Private** (recipient sees via Apex-managed `File_Hub_Entry__Share` row with Read access; sender owns).

### LWC visual design (v5 current)

**Header**
- Book icon (`utility:knowledge_base` with `variant="success"` → green)
- "File Hub" title
- Summary line below: `8 files · 4 categories · 2 unread`
- Refresh button + "Send New File" brand button

**Tabs (home page only):** My Files | Inbox (with unread badge) | Sent

**Category Tile Bar** — single row of 7, color-coded, compact (44px min-height)
- All Files (blue)
- Contracts (purple)
- Catalogs (amber)
- Compliance (green)
- Marketing (pink)
- Personal (cyan)
- Other (gray)

Active tile: solid color fill. Inactive: tinted background + colored icon. Click filters the list.

**Heatmap — "{MONTH} ACTIVITY"** (e.g. "MAY ACTIVITY")
- Calendar grid for current month (28/29/30/31 columns)
- GitHub-green palette: light gray → light/med/strong/dark green based on activity bucket
- Today's cell: navy ring (1.5px border + 2px shadow halo)
- Future days: very soft gray + 70% opacity (not yet happened)
- Tooltip on hover: "May 13 · 3 files" or "May 20 · upcoming"
- Legend (Less ▢ ▢ ▢ ▢ ▢ More) top right

**Search + upload area** — drag-drop or click-browse via `lightning-file-upload`

**File List rows**
- Category-coloured 4px left border stripe
- Coloured chip tag (same brand color, tinted background)
- Filename → click opens native file preview overlay
- Per-row actions: preview / mark-read (if unread) / delete (if sender)

**Recent Activity panel** (home only, last 10 events, last 7 days)
- POV-aware verb: "Sent to X" / "From Y" / "Uploaded"
- Record context: "on Acme Corp" / "on LOAN-00001"
- Relative time: "2h ago" / "yesterday" / "3d ago"

**Send Modal**
- Recipient picker (custom user lookup, auto-shows top 10 on focus)
- Category (required combobox)
- Link to record: None / Reseller / Loan (custom record lookup, auto-shows top 10 on focus)
- Message (optional, 2000 char)
- File upload via `lightning-file-upload`
- Send button (disabled until recipient + category + file all set)

### Tests (21 tests, all passing, ~91% controller coverage)

In `classes/tests/FileHubControllerTest.cls`:
- createEntry: personal / with recipient / with reseller link / missing file / missing category
- markAsRead: by recipient (sets flag) / by sender (no-op, auth check)
- deleteEntry: by sender (succeeds) / by non-sender (throws)
- searchUsers: returns matching / blank term returns top 10
- searchResellers: returns matching
- searchLoans: returns matching
- getCategoryCounts: myFiles / inbox / record view (3 tests)
- getRecentActivity: returns events / recipient sees "Received" verb
- getMonthActivity: returns current month with isToday/isFuture flags
- getFilesForRecord: unsupported object returns empty
- getInbox: filterByCategory applies filter

### Permission set
`File_Hub_User` — granted to your-org-user@example.com. Object CRUD + field-level access (excluding required fields which auto-grant) + Apex class access to FileHubController.

### Manual setup remaining (user must do via Lightning App Builder)
1. **Home page** — drag File Hub LWC to a region, Save & Activate
2. **Reseller record page** — drag File Hub LWC, Save & Activate
3. **Loan record page** — drag File Hub LWC, Save & Activate
4. For Inbox testing: create a 2nd active user (Setup → Users → New User), assign `File_Hub_User` permset to them

### Storage context
Developer Edition org: **20 MB total file storage**, ~893 KB used at last check, ~19 MB free. Plenty for demo (a 500 KB PDF → ~38 file capacity).

---

## 6. Iteration history (File Hub — chronological)

### v1 (initial build)
- Created `File_Hub_Entry__c` object + 10 fields
- Wrote `FileHubController` with basic CRUD
- Built `fileHub` + `fileHubSendModal` + `fileHubUserLookup` LWCs
- Permission set + first deploy
- 13 tests passing

### v2 (category tiles + recent activity)
- Added `getCategoryCounts` Apex method
- Added `getRecentActivity` Apex method
- Replaced dropdown filter with category tile bar
- Added summary line under header
- Added Recent Activity panel at bottom

### v3 (colored design + 30-day heatmap)
- Each category got brand color (purple/amber/green/pink/cyan/gray)
- Tiles colored with active gradient + inactive tinted background
- Added 30-day GitHub-style heatmap with blue palette
- Added category-color left stripes on file list rows
- Hover effects (tile lift, heatmap cell scale)

### v4 (smaller tiles + green icon + auto-show pickers)
- Tiles forced to single row of 7 (was wrapping)
- Reduced tile padding/height for compact look
- Book icon turned green via `variant="success"`
- `searchUsers` 2-char minimum removed → blank term returns top 10
- Created `fileHubRecordLookup` (generic, swappable via lookup-type prop)
- Replaced `lightning-record-picker` in send modal with custom lookup
- Added `searchResellers` + `searchLoans` Apex methods

### v5 (current — month-based heatmap)
- Replaced `getActivityHeatmap()` (30-day rolling) with `getMonthActivity()` (calendar month)
- Added `MonthActivityDTO` wrapper with monthName + daysInMonth + days[]
- HeatmapDayDTO gained `isToday` + `isFuture` flags
- Palette switched from blue to GitHub greens
- Label dynamic: "MAY ACTIVITY" instead of "30-DAY ACTIVITY"
- Today's cell: navy ring outline
- Future days: dim/soft, hover doesn't pop
- Grid columns dynamic (28/29/30/31) via inline style

---


## 8. Open items / V2 candidates

### File Hub V2 features (deferred from MVP)
- **Required Document Checklist** per Reseller (per cluster-4 conversation) — would make the feature interview-killer-level. "Each reseller must have: Signed Contract, Tax Document, Compliance Form. Show status: uploaded / missing / expired."
- **PDF preview modal** — currently uses native Salesforce file preview navigation. Could embed inline.
- **File expiry alerts** — `Expiry_Date__c` field exists, no UI. Could badge + scheduled job + email.
- **Bulk operations** — multi-select delete/archive
- **Storage usage indicator** — header strip showing "X% storage used" (user suggested, not yet built)
- **Custom Metadata categories** — currently hardcoded picklist. MDT-driven would allow admin-managed without deploy.
- **Status__c lifecycle** — Draft / Sent / Archived (would enable archive flow)
- **Cluster 8 interview prep** — 15-20 Q&A for File Hub

### Other deferred items across the project
- TaskTriggerHandler should extend TriggerHandler framework (currently inconsistent)
- `essenWeather.js` still has hardcoded API key on line 17 (was deprecated, replaced by routeWeather, but not cleaned)
- `with sharing` declaration explicit on TaskTriggerHandler + NationalizeService
- Magic strings `'Email'/'Domain'` in ResellerMatchingEngine should be constants or enum
- Custom Metadata for tier thresholds in resellerTierBadge (currently hardcoded JS array)
- Migrate PutsReq endpoint to Named Credential when real core system replaces mock
- Half-hour timezone offset bug in LeadShiftDashboardController (Lagos math doesn't handle India UTC+05:30 correctly)
- Self-rescheduling LeadQueueScheduler lacks try/catch wrap — single failure breaks the chain

---

## 9. How to work with this project

### Deploy
```powershell
sf project deploy start --target-org "Urla Shoes" --ignore-conflicts
```
The `--ignore-conflicts` flag is generally fine because source tracking isn't enabled on this org (`tracksSource: false`).

### Run all tests
```powershell
sf apex run test --target-org "Urla Shoes" --code-coverage --result-format human --wait 15 --test-level RunLocalTests
```

### Run just File Hub tests
```powershell
sf apex run test --target-org "Urla Shoes" --class-names FileHubControllerTest --code-coverage --result-format human --wait 10
```

### Assign File Hub permset
```powershell
sf org assign permset --name File_Hub_User --target-org "Urla Shoes"
```

### Shell notes
- **Project root has a space** in path (`Urla Shoes`) — bash treats it as two args, use PowerShell tool or quote with `"..."`
- `--target-org "Urla Shoes"` needs quotes for the same reason

### Common Apex deploy gotchas hit during File Hub build
1. **Required fields in PermissionSet** — listing `<fieldPermissions>` for a required field throws `cannot deploy to a required field`. Omit; required-field access is auto-granted with object access.
2. **Sharing model conflict with Apex shares** — `<sharingModel>ReadWrite</sharingModel>` makes Read-level Apex shares "trivial" and Salesforce rejects them. Set to `Private` and use Apex-managed shares.
3. **Underscore prefix in Apex identifiers** — `_emptyCategoryMap` is invalid (`Invalid character in identifier`). Use camelCase like `buildEmptyCategoryMap`.
4. **`like` is a SOQL reserved word** in Apex — can't be a local variable name. Use `searchPattern` or similar.
5. **MIXED_DML_OPERATION in tests** — wrap User DML in `System.runAs(new User(Id = UserInfo.getUserId())) { ... }` to bypass.

---


## 11. What "we" most recently completed (May 2026 session highlights)

Session opened with full feature suite (features 1-7) already built. Session work in order:

1. **Cluster 1-7 interview prep** — 148 questions, ~50k words, gitignored prep folder
2. **File Hub v1** — Built from scratch: object, fields, Apex, 3 LWCs, permset, deploy, 13 tests passing
3. **File Hub v2** — Added category tiles + summary line + Recent Activity panel
4. **File Hub v3** — Added colors, compact tiles, 30-day blue heatmap, file row stripes
5. **File Hub v4** — Single-row tiles, native green icon, auto-show user/reseller pickers (no 2-char minimum)
6. **File Hub v5** — Month-based heatmap with GitHub greens, today ring, dynamic month name

Each version was deployed to the org and verified with passing tests. Current state: **21/21 tests pass, FileHubController 91% coverage, deployed and assigned.**

User most recently asked about:
- How file uploading works (computer → ContentDocument flow)
- Storage limits (20 MB in Dev Edition, ~19 MB free)
- Accepted file types (13-extension whitelist in `acceptedFormats`)
- Heatmap behavior (does it turn green on upload? Yes, immediately)

Then asked for this CLAUDE.md file to capture everything.

---

## 12. Where to start next session

**If the user opens the project and says nothing specific:**
1. Read this file (you're doing it now).
2. Check git status to see if anything is uncommitted from last session.
3. Greet the user briefly, reference where we left off (File Hub v5 month heatmap is complete).
4. Wait for direction.



**If the user mentions "File Hub" + V2:** open candidates list in section 8 above. Required Document Checklist is the strongest interview-leveraging addition.

**If the user mentions "storage" or "upload limit":** Dev Edition org has 20 MB file storage total. Current usage ~5%. We discussed adding a header storage indicator but didn't build it.

**If the user mentions "new feature":** review section 4 to make sure it doesn't overlap with existing work. The project is feature-rich already; another big feature dilutes focus. Consider adding to an existing feature instead.

---

## 13. Important commits worth remembering

(git log review next session can refresh, but key milestones:)
- Initial project import (features 1-7 already built)
- API_Config__c migration (keys moved out of source)
- File Hub initial build (this session)
- File Hub v2-v5 iterations (this session)

Branch: `feature/contact-nationalization` (active throughout session). Most work uncommitted at session end — git status will show all File Hub additions as untracked/modified.

---

**End of context document.** Treat this as the canonical answer to "what is this project and where are we?" Update it after meaningful work, especially when finishing a feature iteration or starting a new workstream.
