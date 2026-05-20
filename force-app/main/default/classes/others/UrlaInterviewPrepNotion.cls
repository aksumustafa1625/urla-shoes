/**
 * Publishes the 8 Urla Shoes feature walkthroughs to Notion in STAR format.
 *
 * Run from Anonymous Apex once Notion_Config__c is populated:
 *
 *   // Publish a single feature
 *   UrlaInterviewPrepNotion.publishRouteWeather();
 *
 *   // Or publish everything (one Notion callout per feature, 8 total)
 *   UrlaInterviewPrepNotion.publishAll();
 */
public with sharing class UrlaInterviewPrepNotion {

    public static NotionPublisher.PublishResult publishRouteWeather() {
        return NotionPublisher.publish(buildRouteWeather());
    }

    public static NotionPublisher.PublishResult publishNationalization() {
        return NotionPublisher.publish(buildNationalization());
    }

    public static NotionPublisher.PublishResult publishLoanCreation() {
        return NotionPublisher.publish(buildLoanCreation());
    }

    public static NotionPublisher.PublishResult publishResellerMatching() {
        return NotionPublisher.publish(buildResellerMatching());
    }

    public static NotionPublisher.PublishResult publishLeadQueue() {
        return NotionPublisher.publish(buildLeadQueue());
    }

    public static NotionPublisher.PublishResult publishTierBadge() {
        return NotionPublisher.publish(buildTierBadge());
    }

    public static NotionPublisher.PublishResult publishTaskAggregation() {
        return NotionPublisher.publish(buildTaskAggregation());
    }

    public static NotionPublisher.PublishResult publishFileHub() {
        return NotionPublisher.publish(buildFileHub());
    }

    public static NotionPublisher.PublishResult publishComplianceCockpit() {
        return NotionPublisher.publish(buildComplianceCockpit());
    }

    public static List<NotionPublisher.PublishResult> publishAll() {
        List<NotionPublisher.PublishResult> results = new List<NotionPublisher.PublishResult>();
        results.add(publishRouteWeather());
        results.add(publishNationalization());
        results.add(publishLoanCreation());
        results.add(publishResellerMatching());
        results.add(publishLeadQueue());
        results.add(publishTierBadge());
        results.add(publishTaskAggregation());
        results.add(publishFileHub());
        return results;
    }

    /* ─── FEATURE BUILDERS ──────────────────────────────────────────────── */

    private static NotionPublisher.StarEntry buildComplianceCockpit() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '09. Partner Compliance Cockpit — Autonomous AI Document Compliance';
        e.context = 'Urla Shoes works through a DACH reseller network. Every reseller must keep a set of documents on file (signed contract, tax certificate, liability insurance, bank details). On top of the existing File Hub (a semantic layer over native ContentDocument), the business needed to KNOW, at a glance, which partners are compliant — and to chase the gaps without manual effort. This is a known, largely unsolved gap in the Salesforce ecosystem: no mainstream tool packages required-document checklists, expiry tracking, and an autonomous request loop.';
        e.problem = 'File Hub stored files but could not answer "is this reseller compliant?". There was no per-reseller score, no network-wide view of who is missing what, no expiry awareness, and no way to request a missing document and have the status update itself when the file arrives. Doing this by hand across a partner network does not scale.';
        e.goal = 'Build a Partner Compliance Cockpit in three phases: (1) a per-reseller compliance score + network matrix, (2) AI that reads an uploaded document, classifies it, and extracts its expiry, (3) an autonomous loop that requests missing documents from the partner and auto-closes the request once an AI-validated file is uploaded — with the score updating live.';
        e.constraints = 'Developer Edition limits (Einstein requests, 100-callout limit). Einstein generative AI must route through the Trust Layer (DSGVO/zero-retention) for the German market. Apex cannot extract PDF text natively. Recipient files are Private (Apex-managed shares). Compliance requirements should be admin-editable without a deploy. AI calls must be mockable so tests never depend on a live LLM.';
        e.successCriteria = 'Cockpit shows each reseller as a colored matrix row (MISSING/EXPIRED/EXPIRING/OK per requirement) with a compliance %. "Analyze with AI" classifies a real document via GPT-4o mini and applies category + expiry. "Request Missing Documents" raises Document_Request__c records and emails the primary contact. When a matching file is AI-validated, the request auto-fulfills and the checklist score animates live. 22 Apex tests pass (96-97% on the new services).';
        e.approach = 'Compliance_Requirement__mdt makes requirements admin-managed. ComplianceService computes status + score bulk-safe WITH USER_MODE. DocumentIntelligenceService calls a DocumentClassification Einstein Prompt Template (authored as deployable metadata, not just UI) and parses strict JSON, with a @TestVisible mock hook. ComplianceRequestService raises/auto-fulfills Document_Request__c. A Compliance_Update Lightning Message Channel wires AI-classify → live re-score across components — no polling.';
        e.implementation = new List<String>{
            'Phase 1 — Compliance_Requirement__mdt (4 records) + ComplianceService + complianceCockpit (network matrix) + resellerComplianceChecklist (score ring)',
            'Phase 2 — DocumentIntelligenceService.classifyAndApply via ConnectApi.EinsteinLLM + DocumentClassification GenAiPromptTemplate (GPT-4o mini) + documentAiClassifier LWC',
            'Phase 3 — Document_Request__c + ComplianceRequestService (requestAllGaps sweep, autoFulfill, best-effort email) + documentRequests LWC',
            'Compliance_Update Lightning Message Channel for live cross-component re-score',
            'classifyAndApply auto-closes a matching open request — the validate→act step',
            'All compliance SOQL runs WITH USER_MODE; AI tests use a @TestVisible mock'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = '@AuraEnabled\npublic static ClassificationResult classifyAndApply(Id entryId) {\n    File_Hub_Entry__c entry = [SELECT Id, File_Name__c, Category__c, Related_Reseller__c\n                               FROM File_Hub_Entry__c WHERE Id = :entryId WITH USER_MODE LIMIT 1];\n    // Einstein reads context → strict JSON {category, confidence, expiryDate, summary}\n    String llmText = invokeLlm(buildContext(entry));\n    ClassificationResult res = new ClassificationResult();\n    parseInto(res, llmText);\n    if (VALID_CATEGORIES.contains(res.suggestedCategory)) {\n        entry.Category__c = res.suggestedCategory;\n        if (res.expiryDate != null) entry.Expiry_Date__c = res.expiryDate;\n        update as user entry;\n        // validate → act: close any open request this upload satisfies\n        ComplianceRequestService.autoFulfill(entry);\n        res.applied = true;\n    }\n    return res;\n}';
        e.outcome = 'A closed "detect → request → AI-validate → self-update" loop, fully built and verified live on a Developer Edition org (real GPT-4o mini call classified a contract at 90% confidence). Upgrades File Hub from "document storage" to an autonomous, AI-augmented, DSGVO-aware partner compliance platform. The Prompt Template was authored as deployable metadata rather than UI-only.';
        e.tradeOffs = 'Text-based classification today (file name + note + taxonomy); multimodal (LLM reads the PDF directly) is a template-only upgrade when the org enables it — no Apex change. autoFulfill runs synchronously in the classify path for a crisp demo; high volume would move it async. Email is best-effort (never blocks a request). Coverage on DocumentIntelligenceService is 83% — the uncovered lines are the live LLM block, which cannot run under test.';
        e.references = new List<String>{
            'help.salesforce.com → Einstein Trust Layer (zero-retention, PII masking)',
            'developer.salesforce.com → ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate',
            'developer.salesforce.com → Lightning Message Service',
            'FILE-HUB.md (repo root) — full architecture',
            'Market research: required-doc checklist + expiry lifecycle is an admitted Salesforce ecosystem gap'
        };
        e.futureWork = 'Multimodal Prompt Template (read the PDF directly). Network-wide autonomous sweep on a schedule. Agentforce framing of the request loop. Embeddings-based semantic document search. Per-requirement SLA + escalation.';
        return e;
    }

    private static NotionPublisher.StarEntry buildRouteWeather() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '01. Route & Weather Navigator — Multi-City Logistics Planning';
        e.context = 'Urla Shoes is a Germany-based shoe distributor with a DACH reseller network. Sales reps and logistics planners frequently route between reseller cities (Munich → Cologne → Berlin) and need to know both driving distance/time AND weather impact in one view — weather delays trucking. The reps were juggling Google Maps and weather sites in separate tabs.';
        e.problem = 'There was no consolidated view inside Salesforce that combined a multi-stop route with real-time weather at each waypoint. Reps copy-pasted addresses across two tools and had no way to attach the route artifact to an Opportunity or Account.';
        e.goal = 'Build an LWC inside Salesforce that takes an ordered list of cities, calls Google Maps Directions for the route, calls OpenWeather for each waypoint, and renders an embedded map plus a per-stop weather strip — with an AI-generated risk summary on top.';
        e.constraints = 'Lightning Web Security blocks Google Maps JS API loaded inside an LWC iframe context. API keys cannot live in JS source (auditable in browser). 100-callout limit per Apex transaction. Einstein Prompt Template responses must respect Trust Layer masking.';
        e.successCriteria = 'User enters 3+ cities, presses Plan, and within ~3 seconds sees: (1) Google Map iframe with the route polyline drawn, (2) waypoint cards showing temp/condition/wind, (3) a short AI-written summary like "Heavy rain expected in Cologne — allow +30min".';
        e.approach = 'Visualforce iframe bridge for the map (LWS blocks the direct JS API). Apex service layer aggregates Google Maps + OpenWeather + Einstein in parallel where possible. API keys held in API_Config__c hierarchical custom setting — never in source. postMessage cross-frame protocol carries route data into the iframe.';
        e.implementation = new List<String>{
            'lwc/routeWeather — city input + map iframe + waypoint cards',
            'pages/RouteMapPage — Visualforce shim that loads Google Maps JS API (bypasses LWS sandbox)',
            'services/RouteWeatherAnalysisService — orchestrates Maps + Weather + Einstein',
            'ApiKeyService — reads API_Config__c keys at runtime',
            'Einstein Prompt Template "RouteRiskSummary" — natural-language risk briefing',
            'postMessage protocol — LWC ↔ Visualforce iframe data exchange',
            'Asynchronous: weather callouts batched per-city in one transaction'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = '@AuraEnabled(cacheable=false)\npublic static RouteAnalysis analyzeRoute(List<String> cities) {\n    if (cities == null || cities.size() < 2) {\n        throw new AuraHandledException(\'At least two cities are required\');\n    }\n    ApiKeys keys = ApiKeyService.getKeys();\n    RouteAnalysis result = new RouteAnalysis();\n    result.directions = MapsClient.getDirections(cities, keys.googleMaps);\n    result.weather = WeatherClient.getForecastForCities(cities, keys.openWeather);\n    result.riskSummary = EinsteinClient.summarize(result.directions, result.weather);\n    return result;\n}';
        e.outcome = 'Production-shaped feature. Reps see route + weather + AI summary in one screen inside Salesforce. Visualforce iframe bridge proved a clean workaround for LWS Maps blocking. Pattern reusable for any "external JS SDK trapped by LWS" problem.';
        e.tradeOffs = 'Chose Visualforce iframe over deferred LWS unlock (would have been faster long-term but unpredictable timeline). Sync callouts inside @AuraEnabled — acceptable for ~3 cities; for 10+ cities a Queueable would be required to stay under the 120-second sync limit. AI summary is best-effort — failure does not block the route render.';
        e.references = new List<String>{
            'developer.salesforce.com → Lightning Web Security FAQ',
            'developers.google.com/maps/documentation/javascript/overview',
            'openweathermap.org/api',
            'help.salesforce.com → Einstein Prompt Templates'
        };
        e.futureWork = 'Save planned routes against the Opportunity record. Add traffic-aware ETAs (Maps already returns them — not yet rendered). Cache weather per city for 15 minutes to reduce callouts during repeated planning sessions.';
        return e;
    }

    private static NotionPublisher.StarEntry buildNationalization() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '02. Contact Nationalization — Country Prediction from Name';
        e.context = 'Urla Shoes imports Contacts from trade-show CSV lists with inconsistent country data — many rows have just FirstName + LastName. Sales-ops wants every Contact to carry a likely country code so DACH-region reps can route leads to the right language/timezone.';
        e.problem = 'No internal source of truth for likely nationality from a name. Manual research per row does not scale at the volume Urla imports (~500 contacts per show).';
        e.goal = 'On Contact insert/update, when FirstName is set and Country__c is blank, call the public nationalize.io API to predict country and write it back asynchronously.';
        e.successCriteria = 'After bulk inserting 200 Contacts with only first names, all rows have Predicted_Country__c populated within ~30 seconds, no SOQL/DML governor limit failures, retry behaviour observable in test data.';
        e.approach = 'Trigger handler framework (Kevin O\'Hara pattern) routes ContactTrigger to ContactTriggerHandler. Handler enqueues a Queueable per batch so the callout happens asynchronously — keeps the synchronous DML path fast and stays inside Apex async governor limits. HttpCalloutMock factory enables full callout coverage in tests.';
        e.implementation = new List<String>{
            'triggers/ContactTrigger — single-trigger-per-object pattern',
            'handlers/ContactTriggerHandler — extends TriggerHandler base',
            'services/NationalizeService — Queueable that calls nationalize.io',
            'factories/NationalizeCalloutMock — produces realistic JSON for tests',
            'Field: Contact.Predicted_Country__c (text, 2-char ISO code)',
            'Remote site setting: Nationalize_API (api.nationalize.io)'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class NationalizeService implements Queueable, Database.AllowsCallouts {\n    private final Set<Id> contactIds;\n    public NationalizeService(Set<Id> ids) { this.contactIds = ids; }\n\n    public void execute(QueueableContext qc) {\n        List<Contact> contacts = [SELECT Id, FirstName FROM Contact WHERE Id IN :contactIds];\n        List<Contact> toUpdate = new List<Contact>();\n        for (Contact c : contacts) {\n            if (String.isBlank(c.FirstName)) continue;\n            HttpResponse res = NationalizeClient.predict(c.FirstName);\n            if (res.getStatusCode() == 200) {\n                c.Predicted_Country__c = parseTopCountry(res.getBody());\n                toUpdate.add(c);\n            }\n        }\n        if (!toUpdate.isEmpty()) update toUpdate;\n    }\n}';
        e.outcome = 'Reference implementation for any "DML trigger → async external callout" pattern in this org. ~95% coverage with mocked callouts.';
        e.tradeOffs = 'nationalize.io is rate-limited (1000/day free) — fine for demo but production would need a Named Credential to a paid endpoint or self-hosted model. Predictions are probabilistic — Predicted_Country__c is explicitly named "Predicted" so it does not masquerade as ground truth.';
        e.references = new List<String>{
            'nationalize.io/api',
            'Trigger Framework: github.com/kevinohara80/sfdc-trigger-framework',
            'developer.salesforce.com → HttpCalloutMock'
        };
        e.futureWork = 'Migrate raw endpoint to a Named Credential. Cache predictions per FirstName in a custom object so re-imports avoid re-calling the API. Surface confidence score on the Contact layout.';
        return e;
    }

    private static NotionPublisher.StarEntry buildLoanCreation() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '03. Loan Creation Pipeline — Closed-Won → Loan → External Sync';
        e.context = 'Urla Shoes offers bulk-order resellers a financing instrument ("Loan Feather"). Every Closed-Won Opportunity above a threshold must create a Loan__c record and sync it to a fictional external core lending system within minutes.';
        e.problem = 'Manual loan creation by ops was slow (1-2 days), error-prone, and the external sync was a copy-paste from Salesforce into a separate portal. A failure in the external system silently broke the chain.';
        e.goal = 'Automate: Opportunity Closed-Won → Loan__c insert → callout to mock core lending system → log success/failure → retry transient failures on a schedule.';
        e.successCriteria = 'Closing an Opportunity triggers a Loan within 1 second. External sync logs into Loan_Sync_Log__c. A simulated 500 failure triggers automatic retry on the next scheduler tick. Loan Sync Dashboard LWC shows real-time status.';
        e.approach = 'Trigger handler creates Loan__c synchronously (must persist before async fires). LoanSyncService.Queueable performs the callout. LoanSyncRetryScheduler picks up "Failed" logs every 15 minutes and re-enqueues. PutsReq mock endpoint stands in for the real core system until it exists.';
        e.implementation = new List<String>{
            'handlers/OpportunityTriggerHandler — fires on AfterUpdate when StageName flips to Closed Won',
            'services/LoanCreationService — builds the Loan__c with terms derived from Opp amount + tier',
            'services/LoanSyncService — Queueable; POSTs to PutsReq mock',
            'services/LoanSyncRetryScheduler — Schedulable, runs every 15 minutes',
            'Loan__c + Loan_Sync_Log__c custom objects',
            'lwc/loanSyncDashboard — live status with refreshApex',
            'Remote site setting: PutsReq_CoreSystem (mock endpoint)'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class LoanSyncService implements Queueable, Database.AllowsCallouts {\n    private final Id loanId;\n    public LoanSyncService(Id loanId) { this.loanId = loanId; }\n\n    public void execute(QueueableContext qc) {\n        Loan__c loan = [SELECT Id, External_Id__c, Amount__c, Term_Months__c FROM Loan__c WHERE Id = :loanId];\n        Loan_Sync_Log__c log = new Loan_Sync_Log__c(Loan__c = loan.Id, Attempt_Number__c = nextAttempt(loan.Id));\n        try {\n            HttpResponse res = CoreLendingClient.syncLoan(loan);\n            log.Status__c = res.getStatusCode() == 200 ? \'Success\' : \'Failed\';\n            log.Response_Body__c = res.getBody();\n        } catch (Exception ex) {\n            log.Status__c = \'Failed\';\n            log.Error_Message__c = ex.getMessage();\n        }\n        insert log;\n    }\n}';
        e.outcome = 'Production-shaped pipeline with retry resilience. Dashboard shows real-time sync state. Failure recovery is automatic — ops no longer monitors a queue.';
        e.tradeOffs = 'Scheduled retry every 15 minutes is a coarse SLA; for tighter response a Platform Event-driven retry would be lower latency but adds complexity. Mock endpoint via PutsReq — fine for portfolio, real deployment needs Named Credential to the actual core system. Self-rescheduling scheduler lacks try/catch wrap — a single failure could break the chain (filed as known gap).';
        e.references = new List<String>{
            'developer.salesforce.com → Queueable Apex',
            'putsreq.com (mock HTTP endpoint service)',
            'Trailhead → Salesforce Async Patterns'
        };
        e.futureWork = 'Replace PutsReq with Named Credential. Wrap LoanSyncRetryScheduler.execute in try/catch so a single bad batch does not kill the rescheduling chain. Add exponential backoff on retry attempts.';
        return e;
    }

    private static NotionPublisher.StarEntry buildResellerMatching() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '04. Reseller Matching — Opportunity → Reseller Auto-Assignment';
        e.context = 'Urla Shoes operates through a reseller/partner network. Every Opportunity should be tied to the most appropriate Reseller__c based on contact email domain or geography. Doing this by hand for hundreds of Opps is unsustainable.';
        e.problem = 'Opps were being created with empty Reseller lookups, breaking downstream reseller-tier scoring and commission reporting. Account-to-reseller mappings existed but were not applied automatically.';
        e.goal = 'On Opportunity insert/update, run a matching engine that picks the right Reseller__c using two strategies (Email-domain match, Domain-only Reseller_Mapping__c lookup) and writes the match back with a confidence-tagged log entry.';
        e.successCriteria = 'Inserting an Opportunity with a Contact whose email domain matches an existing Reseller_Mapping__c populates the Reseller lookup automatically. A Reseller_Match_Log__c row captures match type and confidence. Reconciliation job runs nightly to backfill missed matches.';
        e.approach = 'Strategy-pattern matching engine — each match strategy is a method returning the winning Reseller__c or null. Engine tries them in priority order and short-circuits on the first hit. Trigger handler delegates to engine; engine is unit-tested in isolation. Reconciliation as Schedulable Apex for backfill.';
        e.implementation = new List<String>{
            'engines/ResellerMatchingEngine — strategy orchestration',
            'handlers/OpportunityResellerTriggerHandler — wires trigger to engine',
            'services/ResellerMatchLogService — write match-log rows',
            'services/ResellerReconciliationService — Schedulable nightly backfill',
            'Reseller__c + Reseller_Mapping__c + Reseller_Match_Log__c custom objects',
            'Match strategies: Email domain → Reseller, Domain mapping table'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class ResellerMatchingEngine {\n    public ResellerMatchResult match(Opportunity opp, Contact primary) {\n        // Strategy 1: contact email domain → reseller\n        ResellerMatchResult byEmail = matchByEmailDomain(primary);\n        if (byEmail != null) return byEmail.withType(\'Email\');\n\n        // Strategy 2: domain mapping table\n        ResellerMatchResult byMapping = matchByDomainMapping(primary);\n        if (byMapping != null) return byMapping.withType(\'Domain\');\n\n        return null; // reconciliation job will retry later\n    }\n}';
        e.outcome = 'Opps now auto-link to Resellers at insert time. Match-log audit trail enables ops to spot mismatches. Reconciliation backfills handle any race conditions.';
        e.tradeOffs = 'Strategy types are magic strings (\'Email\'/\'Domain\') in the engine — should be constants or an enum (filed as cleanup). Engine runs synchronously inside the trigger — a future high-volume scenario could push it async via Queueable.';
        e.references = new List<String>{
            'Strategy pattern → refactoring.guru/design-patterns/strategy',
            'Schedulable Apex docs'
        };
        e.futureWork = 'Extract match-type strings to a typed enum. Add geographic-proximity strategy as the third tier. Surface match confidence on the Opp record page via a Tier Badge–style LWC.';
        return e;
    }

    private static NotionPublisher.StarEntry buildLeadQueue() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '05. Lead Queue + Shift Dashboard — Round-Robin with SLA + Platform Events';
        e.context = 'Urla Shoes runs an inbound lead funnel with reps in three regions (DACH morning shift, US afternoon shift, India night shift). Leads must route to the on-duty rep, respect a SLA window, and the dashboard must update in real time as reps log in/out.';
        e.problem = 'Default Salesforce queue assignment did not respect shift coverage. Leads handed to an off-duty rep sat for hours. There was no live dashboard showing which reps are on-shift and how many leads are aging past SLA.';
        e.goal = 'Build a custom round-robin assignment engine with shift awareness and SLA enforcement. Surface live shift state on a dashboard LWC driven by Platform Events.';
        e.successCriteria = 'A new Lead is assigned within 30 seconds to a rep currently on shift. If unanswered past SLA, it surfaces in SLA_Breach_Log__c and re-routes. Dashboard shows green/red shift indicators that flip instantly when a rep clocks in/out.';
        e.approach = 'Round-robin engine pulls active reps from Lead_Queue__c filtered by current Shift__c. Self-rescheduling Schedulable Apex runs every 5 minutes for SLA polling. Platform Event Lead_Shift_Event__e fires on shift changes — LWC subscribes via empApi for live updates without polling.';
        e.implementation = new List<String>{
            'engines/LeadQueueProcessor — round-robin selection logic',
            'services/LeadQueueService — assign Lead.OwnerId + log',
            'services/LeadQueueScheduler — self-rescheduling, runs every 5 minutes',
            'lwc/leadShiftDashboard — subscribes to Lead_Shift_Event__e via empApi',
            'Platform Event: Lead_Shift_Event__e',
            'Custom objects: Lead_Queue__c, Shift__c, SLA_Breach_Log__c'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class LeadQueueProcessor {\n    public Id nextEligibleRep(Datetime nowUtc) {\n        // Pull reps whose shift covers nowUtc, ordered by last-assigned-at (oldest first)\n        List<Lead_Queue__c> eligible = [\n            SELECT Id, Rep__c, Last_Assigned__c\n            FROM Lead_Queue__c\n            WHERE Active__c = true\n              AND Shift__r.Start__c <= :nowUtc\n              AND Shift__r.End__c >= :nowUtc\n            ORDER BY Last_Assigned__c ASC NULLS FIRST\n            LIMIT 1\n        ];\n        return eligible.isEmpty() ? null : eligible[0].Rep__c;\n    }\n}';
        e.outcome = 'Leads now reach an on-duty rep within seconds. Dashboard is live (no refresh button needed). SLA breaches are observable and auditable.';
        e.tradeOffs = 'Half-hour timezone offsets (India UTC+05:30) are not perfectly handled — math assumes whole-hour offsets (known bug, filed). Self-rescheduling scheduler lacks try/catch — a single failure stops the chain. Platform Events have at-least-once delivery — UI should be idempotent (it is).';
        e.references = new List<String>{
            'developer.salesforce.com → Platform Events',
            'developer.salesforce.com → empApi LWC module',
            'Schedulable Apex self-rescheduling pattern'
        };
        e.futureWork = 'Fix half-hour timezone arithmetic for India shift. Add try/catch to LeadQueueScheduler.execute. Add workload-balancing (not pure round-robin) — weight by current open lead count.';
        return e;
    }

    private static NotionPublisher.StarEntry buildTierBadge() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '06. Reseller Tier Badge — Visual Score Indicator';
        e.context = 'Reseller__c records carry a numeric performance score (Score__c) updated by aggregation from related Tasks and Opportunities. Reps wanted a glanceable Bronze/Silver/Gold/Platinum badge on the reseller record page instead of reading a raw number.';
        e.problem = 'Numeric scores are hard to interpret at a glance. Reps wanted a visual cue (color + tier name) so they could prioritise high-value resellers without context-switching to a separate report.';
        e.goal = 'A small LWC pinned to the Reseller__c record page that reads Score__c and renders a coloured tier badge — Bronze < 50, Silver 50-99, Gold 100-249, Platinum 250+.';
        e.successCriteria = 'Opening any Reseller__c record shows the badge in the highlights panel. Score change triggers an immediate re-render. Coverage by tier is testable via mock data.';
        e.approach = 'Pure presentation LWC consuming the score via @api recordId + @wire(getRecord). Thresholds defined as a JS array constant — simple, deployable, but unfortunately not admin-editable without redeploy.';
        e.implementation = new List<String>{
            'lwc/resellerTierBadge — single-component LWC, no Apex',
            'Wire: getRecord with Score__c field',
            'Tier ladder defined as JS const TIERS = [{ min:0, label:"Bronze", color:"#cd7f32" }, ...]',
            'CSS for badge pill + color tokens'
        };
        e.codeLanguage = 'javascript';
        e.codeSnippet = 'import { LightningElement, api, wire } from \'lwc\';\nimport { getRecord, getFieldValue } from \'lightning/uiRecordApi\';\nimport SCORE_FIELD from \'@salesforce/schema/Reseller__c.Score__c\';\n\nconst TIERS = [\n  { min: 250, label: \'Platinum\', color: \'#0070d2\' },\n  { min: 100, label: \'Gold\',     color: \'#ffb400\' },\n  { min: 50,  label: \'Silver\',   color: \'#aaaaaa\' },\n  { min: 0,   label: \'Bronze\',   color: \'#cd7f32\' }\n];\n\nexport default class ResellerTierBadge extends LightningElement {\n    @api recordId;\n    @wire(getRecord, { recordId: \'$recordId\', fields: [SCORE_FIELD] }) reseller;\n\n    get tier() {\n        const score = getFieldValue(this.reseller.data, SCORE_FIELD) ?? 0;\n        return TIERS.find(t => score >= t.min);\n    }\n}';
        e.outcome = 'Single-component LWC ships in <100 lines of JS. Reps adopted it instantly — became the highlights-panel default.';
        e.tradeOffs = 'Tier thresholds live in JS — admin-friendly Custom Metadata Types would be better but adds complexity for a 4-tier ladder that rarely changes. Color tokens hardcoded — should use SLDS design tokens or a theme custom property for dark-mode support.';
        e.references = new List<String>{
            'developer.salesforce.com → uiRecordApi wire adapters',
            'SLDS design tokens'
        };
        e.futureWork = 'Move thresholds to a Tier_Threshold__mdt custom metadata type so ops can rebalance without deploy. Add a tooltip showing the score breakdown (which factors contributed how much).';
        return e;
    }

    private static NotionPublisher.StarEntry buildTaskAggregation() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '07. Task → Opportunity Score Aggregation — Engagement-Driven Score';
        e.context = 'Sales-ops wants Opportunity Score__c to reflect engagement intensity — completed Tasks (calls, emails, meetings) should bump the score, surfacing actively-worked Opps to the top of pipeline views.';
        e.problem = 'Salesforce native does not roll up Task counts/types to an Opportunity Score field. Manual reports existed but were not actionable inside record pages.';
        e.goal = 'On Task insert/update/delete, recompute the parent Opportunity\'s Score__c based on Task type and completion state, all inside one bulk-safe trigger handler.';
        e.successCriteria = 'Logging a completed Call Task on an Opp increments its Score__c immediately. Bulk-inserting 200 Tasks across 50 Opps stays within governor limits (1 SOQL, 1 DML).';
        e.approach = 'TaskTrigger delegates to TaskTriggerHandler which collects affected Opp ids in a Set, runs one aggregate query, computes new scores in-memory, performs one DML. Score formula is a static private method — easy to test in isolation.';
        e.implementation = new List<String>{
            'triggers/TaskTrigger — fires on after-insert, after-update, after-delete',
            'handlers/TaskTriggerHandler — bulk-safe aggregation + score recompute',
            'Score formula: completed Call=+5, Email=+2, Meeting=+10',
            'Single SOQL aggregate query per trigger execution',
            'Single DML update on affected Opportunities'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class TaskTriggerHandler {\n    public static void recomputeScores(Set<Id> oppIds) {\n        if (oppIds.isEmpty()) return;\n\n        AggregateResult[] grouped = [\n            SELECT WhatId, Type, COUNT(Id) cnt\n            FROM Task\n            WHERE WhatId IN :oppIds AND Status = \'Completed\'\n            GROUP BY WhatId, Type\n        ];\n\n        Map<Id, Integer> scoreByOpp = new Map<Id, Integer>();\n        for (AggregateResult r : grouped) {\n            Id oppId = (Id) r.get(\'WhatId\');\n            Integer cnt = (Integer) r.get(\'cnt\');\n            Integer weight = weightForType((String) r.get(\'Type\'));\n            scoreByOpp.put(oppId, (scoreByOpp.get(oppId) == null ? 0 : scoreByOpp.get(oppId)) + cnt * weight);\n        }\n\n        List<Opportunity> updates = new List<Opportunity>();\n        for (Id oppId : oppIds) {\n            updates.add(new Opportunity(Id = oppId, Score__c = scoreByOpp.get(oppId) == null ? 0 : scoreByOpp.get(oppId)));\n        }\n        update updates;\n    }\n}';
        e.outcome = 'Opp Score updates in real time as reps log Tasks. Bulk-safe — no governor limit breach in 200-Task inserts.';
        e.tradeOffs = 'TaskTriggerHandler does NOT extend the shared TriggerHandler framework (inconsistency with other handlers — filed as cleanup). Score weights are magic numbers in the handler — should be custom metadata.';
        e.references = new List<String>{
            'developer.salesforce.com → SOQL Aggregate Queries',
            'Trailhead → Apex Trigger Best Practices'
        };
        e.futureWork = 'Refactor TaskTriggerHandler to extend the shared TriggerHandler base class. Move score weights to Score_Weight__mdt. Add Task age decay so old Tasks contribute less.';
        return e;
    }

    private static NotionPublisher.StarEntry buildFileHub() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = '08. File Hub — Partner Document Center Over ContentDocument';
        e.context = 'Urla Shoes\' reseller network exchanges contracts, catalogs, compliance docs, marketing assets — but native Salesforce file management surfaces only raw ContentDocument with no business semantics (no sender, recipient, category, related-record context). Files were scattered with no inbox/sent metaphor.';
        e.problem = 'No way to "send a file" to another internal user with a category, a related Reseller/Loan, and a message. No inbox showing files received. No record-page view scoped to that record\'s files. No activity summary or unread badge.';
        e.goal = 'Build a Partner Document Center LWC that overlays sender/recipient/category/record-link metadata on top of native ContentDocument. Surfaces on Home (3 tabs: My Files / Inbox / Sent) and on Reseller / Loan record pages (record-scoped).';
        e.successCriteria = '21 Apex tests pass with 91% controller coverage. User can upload a personal file, send a file to another user (auto-shared with Read access), see inbox unread count, filter by category tile, see month-based activity heatmap with today highlighted, preview files inline, delete own sent files.';
        e.approach = 'Custom object File_Hub_Entry__c wraps ContentDocument with business fields. Apex-managed sharing via File_Hub_Entry__Share gives the recipient Read access. Object sharing is Private so Apex shares are meaningful. with sharing on the main controller; a without sharing helper (FileHubSharingHelper) handles the recipient-marks-read flow. GitHub-style heatmap rendered from a single getMonthActivity aggregate query.';
        e.implementation = new List<String>{
            'objects/File_Hub_Entry__c — 12 fields wrapping ContentDocument with business semantics',
            'classes/FileHubController — 14 AuraEnabled methods (CRUD + read + search)',
            'classes/FileHubSharingHelper — without-sharing helper for recipient mark-as-read',
            'lwc/fileHub — main surface, multi-target (Home + Reseller + Loan record pages)',
            'lwc/fileHubSendModal — recipient/category/record/message/file picker',
            'lwc/fileHubUserLookup + fileHubRecordLookup — auto-show top 10 on focus',
            'permissionsets/File_Hub_User — object CRUD + field perms + Apex access',
            'tests/FileHubControllerTest — 21 tests, 91% coverage on FileHubController'
        };
        e.codeLanguage = 'apex';
        e.codeSnippet = '@AuraEnabled(cacheable=true)\npublic static MonthActivityDTO getMonthActivity() {\n    Id me = UserInfo.getUserId();\n    Date today = Date.today();\n    Date firstOfMonth = Date.newInstance(today.year(), today.month(), 1);\n    Integer daysInMonth = Date.daysInMonth(today.year(), today.month());\n\n    AggregateResult[] grouped = [\n        SELECT DAY_ONLY(CreatedDate) d, COUNT(Id) cnt\n        FROM File_Hub_Entry__c\n        WHERE (Sender__c = :me OR Recipient__c = :me)\n          AND CreatedDate >= :firstOfMonth\n        GROUP BY DAY_ONLY(CreatedDate)\n    ];\n    Map<Integer, Integer> countByDay = new Map<Integer, Integer>();\n    for (AggregateResult r : grouped) {\n        Date d = (Date) r.get(\'d\');\n        countByDay.put(d.day(), (Integer) r.get(\'cnt\'));\n    }\n\n    MonthActivityDTO out = new MonthActivityDTO();\n    out.monthName = DateTime.newInstance(firstOfMonth, Time.newInstance(0,0,0,0)).format(\'MMMM\').toUpperCase();\n    out.daysInMonth = daysInMonth;\n    out.todayDayOfMonth = today.day();\n    out.days = buildDays(countByDay, today, daysInMonth);\n    return out;\n}';
        e.outcome = 'Five iterations (v1 → v5) shipped in a single session. v5 (current) features: colored category tile bar, month-based GitHub-green heatmap with today ring + dimmed future days, category-coded row stripes, custom user/reseller/loan pickers that show top 10 on focus, recent activity panel. 21/21 tests green. Deployed.';
        e.tradeOffs = 'Object sharing set to Private after a deploy error proved that ReadWrite default makes Apex Read shares "trivial". Required fields cannot have fieldPermissions entries in a permission set (auto-granted with object access). Categories are picklist values — admin-editable but not via CMT.';
        e.references = new List<String>{
            'developer.salesforce.com → ContentDocument / ContentVersion / ContentDocumentLink',
            'developer.salesforce.com → Apex-Managed Sharing',
            'FILE-HUB.md (repo root) — full feature documentation',
            'CLAUDE.md section 5 — iteration history v1–v5'
        };
        e.futureWork = 'Required Document Checklist per Reseller (the interview-killer V2 candidate). Storage usage header strip. Status__c lifecycle (Draft/Sent/Archived). Custom Metadata categories. Inline PDF preview modal.';
        return e;
    }
}
