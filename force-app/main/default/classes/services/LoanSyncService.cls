/**
 * @description : Queueable that POSTs Loan__c records to the core system and flips
 *                isSynced__c when the core system confirms. v2 adds:
 *                  - smart response parsing (JSON confirmations OR plain text)
 *                  - per-attempt audit logging in Loan_Sync_Log__c
 *                  - retry counter + last-attempt timestamp on Loan__c
 *                  - AuraEnabled retry entry point (from LWC "Retry Now" button)
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 *
 * Design notes:
 * - Queueable + Database.AllowsCallouts — triggers cannot issue HTTP synchronously.
 * - One callout per batch (JSON array), keeps us at 1 of 100 callouts/transaction
 *   even on bulk inserts of 200 Opps.
 * - Response parsing is defensive: if the core system speaks JSON with a
 *   "confirmations" array, we extract per-loan confirmation numbers; if it replies
 *   with plain text ("Hello World"), we fall back to a generic "OK" marker so the
 *   Loan still flips to synced. This lets us deploy BEFORE the PutsReq bucket is
 *   upgraded, and automatically enrich once it is.
 * - Every attempt writes a Loan_Sync_Log__c row — even failures — so operators
 *   get a permanent audit trail for compliance + debugging.
 */
public with sharing class LoanSyncService implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final String CORE_SYSTEM_ENDPOINT =
        'https://putsreq.com/y1FQESg0aesG5ycLqVXu';

    // Hard ceiling on automatic retries. Beyond this a human should investigate;
    // the retry scheduler skips loans with Retry_Count__c >= MAX_RETRIES.
    public static final Integer MAX_RETRIES = 5;

    private List<Id> loanIds;

    public LoanSyncService(List<Id> loanIds) {
        this.loanIds = loanIds;
    }

    /**
     * AuraEnabled retry entry point for the LWC "Retry Now" button. Enqueues a
     * fresh sync job for a single Loan, bypassing the retry-count ceiling (the
     * user explicitly asked for this, so they know what they're doing).
     */
    @AuraEnabled
    public static void retry(Id loanId) {
        if (loanId == null) {
            throw new AuraHandledException('loanId is required.');
        }
        System.enqueueJob(new LoanSyncService(new List<Id>{ loanId }));
    }

    public void execute(QueueableContext ctx) {
        List<Loan__c> loans = [
            SELECT Id, Loan_Amount__c, Term_In_Months__c, Monthly_Payments__c, Retry_Count__c
            FROM Loan__c
            WHERE Id IN :loanIds
        ];

        if (loans.isEmpty()) {
            return;
        }

        String requestBody = buildPayload(loans);
        CalloutResult result = sendToCoreSystem(requestBody);

        // Parse per-loan confirmations from a JSON response. Null-safe: if the
        // response isn't JSON or is missing the "confirmations" key, we get an
        // empty map and every loan still succeeds with a generic OK marker.
        Map<String, String> sfIdToConfirmation = extractConfirmations(result.body);

        DateTime now = System.now();
        List<Loan__c> loanUpdates = new List<Loan__c>();
        List<Loan_Sync_Log__c> logs = new List<Loan_Sync_Log__c>();

        for (Loan__c l : loans) {
            Integer currentRetry = (l.Retry_Count__c == null ? 0 : l.Retry_Count__c.intValue());
            Integer attemptNumber = currentRetry + 1;
            Loan__c upd = new Loan__c(Id = l.Id, Last_Sync_Attempt__c = now);

            if (result.success) {
                upd.isSynced__c = true;
                upd.Retry_Count__c = 0; // reset: a success erases prior failure history
                upd.Sync_Error__c = null;

                // Prefer a real confirmation number; fall back to 'OK' so operators
                // can still distinguish "never synced" (blank) from "synced via
                // plain-text endpoint" (OK). Truncate to the 80-char field limit.
                String confirmation = sfIdToConfirmation.get(l.Id);
                if (String.isBlank(confirmation)) {
                    confirmation = 'OK';
                }
                upd.Core_System_Ref__c = confirmation.left(80);
            } else {
                upd.isSynced__c = false;
                upd.Retry_Count__c = attemptNumber;
                // Keep error message short — it's a Text(255), not a long-text.
                upd.Sync_Error__c = (result.errorMessage == null
                    ? 'HTTP ' + result.statusCode
                    : result.errorMessage).left(255);
            }
            loanUpdates.add(upd);

            logs.add(new Loan_Sync_Log__c(
                Loan__c = l.Id,
                Attempt_Number__c = attemptNumber,
                HTTP_Status__c = result.statusCode,
                Success__c = result.success,
                Request_Body__c = requestBody.left(32768),
                Response_Body__c = (result.body == null ? null : result.body.left(32768)),
                Error_Message__c = (result.errorMessage == null ? null : result.errorMessage.left(255))
            ));
        }

        update loanUpdates;
        insert logs;
    }

    /**
     * Builds the request payload the core system expects. Extracted so tests can
     * assert on the exact JSON shape without running a callout.
     */
    @TestVisible
    private static String buildPayload(List<Loan__c> loans) {
        List<Map<String, Object>> wrapper = new List<Map<String, Object>>();
        for (Loan__c l : loans) {
            wrapper.add(new Map<String, Object>{
                'Loan' => new Map<String, Object>{
                    'sf_id'            => l.Id,
                    'loan_amount'      => l.Loan_Amount__c == null ? null : String.valueOf(l.Loan_Amount__c),
                    'term_in_months'   => l.Term_In_Months__c == null ? null : String.valueOf(l.Term_In_Months__c.intValue()),
                    'monthly_payments' => l.Monthly_Payments__c
                }
            });
        }
        return JSON.serialize(wrapper);
    }

    /**
     * Small value object so callers can read status + body + error without having
     * to repeat try/catch logic. Using a public inner class so tests can construct
     * fakes.
     */
    @TestVisible
    public class CalloutResult {
        public Boolean success;
        public Integer statusCode;
        public String body;
        public String errorMessage;
    }

    @TestVisible
    private static CalloutResult sendToCoreSystem(String jsonBody) {
        CalloutResult result = new CalloutResult();
        HttpRequest req = new HttpRequest();
        req.setEndpoint(CORE_SYSTEM_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setBody(jsonBody);
        req.setTimeout(20000);

        try {
            HttpResponse res = new Http().send(req);
            result.statusCode = res.getStatusCode();
            result.body = res.getBody();
            result.success = result.statusCode != null
                && result.statusCode >= 200
                && result.statusCode < 300;
            if (!result.success) {
                result.errorMessage = 'Non-2xx response: ' + result.statusCode;
            }
        } catch (Exception e) {
            result.success = false;
            result.statusCode = 0;
            result.errorMessage = e.getMessage();
        }
        return result;
    }

    /**
     * Extracts sf_id -> confirmation_number pairs from a core-system JSON response.
     * Expected shape:
     *   { "status": "success",
     *     "confirmations": [ { "sf_id": "a0X...", "confirmation_number": "CS-..." }, ... ] }
     *
     * Returns an empty map if:
     *   - response is blank, plain text, or malformed JSON
     *   - the shape is JSON but missing "confirmations"
     * Callers must handle the empty-map case and assume success via HTTP status alone.
     */
    @TestVisible
    private static Map<String, String> extractConfirmations(String responseBody) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(responseBody)) {
            return out;
        }
        try {
            Object parsed = JSON.deserializeUntyped(responseBody);
            if (!(parsed instanceof Map<String, Object>)) {
                return out;
            }
            Map<String, Object> root = (Map<String, Object>) parsed;
            Object confRaw = root.get('confirmations');
            if (!(confRaw instanceof List<Object>)) {
                return out;
            }
            for (Object c : (List<Object>) confRaw) {
                if (!(c instanceof Map<String, Object>)) {
                    continue;
                }
                Map<String, Object> conf = (Map<String, Object>) c;
                String sfId = (String) conf.get('sf_id');
                String confNum = (String) conf.get('confirmation_number');
                if (String.isNotBlank(sfId) && String.isNotBlank(confNum)) {
                    out.put(sfId, confNum);
                }
            }
        } catch (Exception e) {
            // Plain-text response like "Hello World" lands here. We return an empty
            // map so the caller falls back to generic success without logging an
            // error — this isn't a failure, it's just a simpler endpoint.
        }
        return out;
    }

    /**
     * Builds the loanSyncDashboard LWC payload: current loan state + its log history.
     * Returns a raw Map so the component can bind each field without an Apex wrapper.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getDashboard(Id loanId) {
        if (loanId == null) {
            throw new AuraHandledException('loanId is required.');
        }
        Loan__c l = [
            SELECT Id, Name, Loan_Amount__c, Term_In_Months__c, Monthly_Payments__c,
                   isSynced__c, Core_System_Ref__c, Last_Sync_Attempt__c,
                   Sync_Error__c, Retry_Count__c
            FROM Loan__c
            WHERE Id = :loanId
            LIMIT 1
        ];
        List<Loan_Sync_Log__c> logs = [
            SELECT Id, Name, Attempt_Number__c, HTTP_Status__c, Success__c,
                   Request_Body__c, Response_Body__c, Error_Message__c, CreatedDate
            FROM Loan_Sync_Log__c
            WHERE Loan__c = :loanId
            ORDER BY CreatedDate DESC
            LIMIT 20
        ];
        return new Map<String, Object>{
            'loan' => l,
            'logs' => logs,
            'maxRetries' => MAX_RETRIES
        };
    }
}
