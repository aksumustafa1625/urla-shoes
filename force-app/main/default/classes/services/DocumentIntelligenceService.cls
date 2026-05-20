/**
 * AI document intelligence for the Partner Compliance feature.
 *
 * Given a File_Hub_Entry__c, it sends document context (file name, type, sender note,
 * reseller, and the live category taxonomy) to an Einstein Prompt Template through the
 * Trust Layer, then parses a structured JSON classification:
 *
 *   { "category": "...", "confidence": 0-100, "expiryDate": "YYYY-MM-DD|null", "summary": "..." }
 *
 * It validates the suggested category against the File Hub picklist, then APPLIES it —
 * setting Category__c (+ Expiry_Date__c when extracted) on the entry. This is the
 * autonomous "classify → extract → validate → act" loop: the document files itself
 * against the reseller's compliance checklist and the score updates live.
 *
 * Einstein is invoked exactly like the proven RouteWeatherAnalysisService pattern
 * (ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate). Tests inject a mock LLM
 * response via the @TestVisible hook so coverage never depends on a live Einstein call.
 *
 * Multimodal upgrade path: when the org enables multimodal Prompt Templates, the same
 * template can accept the file itself (Prompt Template Attachment) so the LLM reads the
 * PDF directly — no code change here beyond the template definition.
 */
public with sharing class DocumentIntelligenceService {

    @TestVisible private static String mockLlmText; // tests inject the raw LLM JSON here

    private static final String PROMPT_TEMPLATE = 'DocumentClassification';
    private static final String INPUT_PARAM = 'Input:documentContext';

    private static final Set<String> VALID_CATEGORIES = new Set<String>{
        'Contract', 'Tax Document', 'Insurance', 'Bank Details',
        'Catalog', 'Compliance', 'Marketing', 'Personal', 'Other'
    };

    /* ─── DTOs ──────────────────────────────────────────────────────────── */

    public class EntryInfo {
        @AuraEnabled public Id entryId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public String category;
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public String contentDocumentId;
    }

    public class ClassificationResult {
        @AuraEnabled public Id entryId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String suggestedCategory;
        @AuraEnabled public Integer confidence;     // 0-100
        @AuraEnabled public Date expiryDate;
        @AuraEnabled public String summary;
        @AuraEnabled public String previousCategory;
        @AuraEnabled public Boolean applied;
        @AuraEnabled public String message;         // human-friendly status for the toast
    }

    /* ─── PUBLIC API ────────────────────────────────────────────────────── */

    @AuraEnabled(cacheable=true)
    public static List<EntryInfo> getResellerEntries(Id resellerId) {
        if (resellerId == null) {
            throw new AuraHandledException('A reseller id is required');
        }
        List<EntryInfo> out = new List<EntryInfo>();
        for (File_Hub_Entry__c e : [
            SELECT Id, File_Name__c, File_Extension__c, Category__c,
                   Expiry_Date__c, ContentDocument_Id__c
            FROM File_Hub_Entry__c
            WHERE Related_Reseller__c = :resellerId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            EntryInfo info = new EntryInfo();
            info.entryId = e.Id;
            info.fileName = e.File_Name__c;
            info.fileExtension = e.File_Extension__c;
            info.category = e.Category__c;
            info.expiryDate = e.Expiry_Date__c;
            info.contentDocumentId = e.ContentDocument_Id__c;
            out.add(info);
        }
        return out;
    }

    @AuraEnabled
    public static ClassificationResult classifyAndApply(Id entryId) {
        if (entryId == null) {
            throw new AuraHandledException('An entry id is required');
        }

        List<File_Hub_Entry__c> entries = [
            SELECT Id, File_Name__c, File_Extension__c, Category__c, Expiry_Date__c,
                   Message__c, Related_Reseller__c, Related_Reseller__r.Name
            FROM File_Hub_Entry__c
            WHERE Id = :entryId
            WITH USER_MODE
            LIMIT 1
        ];
        if (entries.isEmpty()) {
            throw new AuraHandledException('File Hub entry not found or not accessible');
        }
        File_Hub_Entry__c entry = entries[0];

        ClassificationResult result = new ClassificationResult();
        result.entryId = entry.Id;
        result.fileName = entry.File_Name__c;
        result.previousCategory = entry.Category__c;
        result.applied = false;

        String llmText;
        try {
            llmText = invokeLlm(buildContext(entry));
        } catch (Exception ex) {
            result.message = 'AI service unavailable: ' + ex.getMessage();
            return result;
        }

        parseInto(result, llmText);

        if (String.isBlank(result.suggestedCategory) || !VALID_CATEGORIES.contains(result.suggestedCategory)) {
            result.message = 'AI could not confidently classify this document.';
            return result;
        }

        entry.Category__c = result.suggestedCategory;
        if (result.expiryDate != null) {
            entry.Expiry_Date__c = result.expiryDate;
        }
        update as user entry;

        // Validate → act: close any open document request this upload satisfies.
        Integer fulfilled = ComplianceRequestService.autoFulfill(entry);

        result.applied = true;
        result.message = 'Classified as ' + result.suggestedCategory
            + (result.confidence != null ? ' (' + result.confidence + '% confidence)' : '')
            + (result.expiryDate != null ? ' · valid until ' + result.expiryDate.format() : '')
            + (fulfilled > 0 ? ' · fulfilled an open request' : '');
        return result;
    }

    /* ─── INTERNALS ─────────────────────────────────────────────────────── */

    private static String buildContext(File_Hub_Entry__c entry) {
        Set<String> expiryCats = new Set<String>();
        for (Compliance_Requirement__mdt req : [
            SELECT Document_Category__c, Has_Expiry__c
            FROM Compliance_Requirement__mdt
            WHERE Active__c = true AND Has_Expiry__c = true
        ]) {
            expiryCats.add(req.Document_Category__c);
        }

        String resellerName = entry.Related_Reseller__r == null ? 'N/A' : entry.Related_Reseller__r.Name;
        List<String> lines = new List<String>();
        lines.add('Classify this partner document for a German shoe distributor.');
        lines.add('File name: ' + (entry.File_Name__c == null ? '' : entry.File_Name__c));
        lines.add('File type: ' + (entry.File_Extension__c == null ? '' : entry.File_Extension__c));
        lines.add('Sender note: ' + (entry.Message__c == null ? '(none)' : entry.Message__c));
        lines.add('Reseller: ' + resellerName);
        lines.add('Allowed categories: ' + String.join(new List<String>(VALID_CATEGORIES), ', '));
        lines.add('Categories that carry an expiry date: ' + String.join(new List<String>(expiryCats), ', '));
        lines.add('Return ONLY strict JSON: '
            + '{"category":"<one allowed category>","confidence":<0-100>,'
            + '"expiryDate":"<YYYY-MM-DD or null>","summary":"<one sentence>"}');
        return String.join(lines, '\n');
    }

    /**
     * Invokes the Einstein Prompt Template and returns the raw generated text.
     * In test context returns the injected mock so no live callout occurs.
     */
    private static String invokeLlm(String documentContext) {
        if (Test.isRunningTest() || mockLlmText != null) {
            return mockLlmText;
        }
        Map<String, ConnectApi.WrappedValue> inputParams =
            new Map<String, ConnectApi.WrappedValue>();
        ConnectApi.WrappedValue ctx = new ConnectApi.WrappedValue();
        ctx.value = documentContext;
        inputParams.put(INPUT_PARAM, ctx);

        ConnectApi.EinsteinPromptTemplateGenerationsInput promptInput =
            new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        promptInput.inputParams = inputParams;
        promptInput.isPreview = false;
        promptInput.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        promptInput.additionalConfig.applicationName = 'PromptTemplateGenerationsInvocable';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation response =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(PROMPT_TEMPLATE, promptInput);

        if (response != null && response.generations != null && !response.generations.isEmpty()) {
            return response.generations[0].text;
        }
        return null;
    }

    /** Parses the LLM JSON (tolerating ```json fences) into the result DTO. */
    @TestVisible
    private static void parseInto(ClassificationResult result, String llmText) {
        if (String.isBlank(llmText)) {
            result.message = 'AI returned no content.';
            return;
        }
        String cleanJson = stripFences(llmText);
        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cleanJson);
            if (parsed.get('category') != null) {
                result.suggestedCategory = String.valueOf(parsed.get('category')).trim();
            }
            if (parsed.get('confidence') != null) {
                result.confidence = Integer.valueOf(Decimal.valueOf(String.valueOf(parsed.get('confidence'))));
            }
            if (parsed.get('summary') != null) {
                result.summary = String.valueOf(parsed.get('summary'));
            }
            Object expiry = parsed.get('expiryDate');
            if (expiry != null) {
                result.expiryDate = parseDate(String.valueOf(expiry));
            }
        } catch (Exception ex) {
            result.message = 'AI response could not be parsed: ' + ex.getMessage();
        }
    }

    private static String stripFences(String text) {
        String t = text.trim();
        if (t.startsWith('```')) {
            // remove leading ```json / ``` and trailing ```
            t = t.replaceFirst('^```[a-zA-Z]*\\s*', '');
            if (t.endsWith('```')) {
                t = t.substring(0, t.length() - 3);
            }
        }
        return t.trim();
    }

    @TestVisible
    private static Date parseDate(String value) {
        if (String.isBlank(value) || value.equalsIgnoreCase('null')) {
            return null;
        }
        List<String> parts = value.trim().substringBefore('T').split('-');
        if (parts.size() != 3) {
            return null;
        }
        try {
            return Date.newInstance(
                Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), Integer.valueOf(parts[2])
            );
        } catch (Exception ex) {
            return null;
        }
    }
}
