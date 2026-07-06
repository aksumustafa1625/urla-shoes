/**
 * @description : Queueable service that enriches Contact records with predicted country
 *                data from the public Nationalize.io API. For each Contact, it performs
 *                an HTTP GET to https://api.nationalize.io/?name=<FirstName>, parses the
 *                JSON response, picks the country with the highest probability, and
 *                writes the result to Contact.Nationalized_Country__c in the format
 *                "CODE, Country Name" (e.g. "BD, Bangladesh").
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Contact Nationalization
 *
 * Design notes:
 * - Implements Queueable + Database.AllowsCallouts because Apex triggers cannot make
 *   synchronous HTTP callouts. The trigger handler enqueues this job so the callout
 *   runs in a separate, async transaction.
 * - The class operates on a list of Ids (not sObjects) so the payload that Salesforce
 *   serialises into the async transaction stays small and free of stale field values.
 * - One callout is made per contact because Nationalize.io does not support batch
 *   lookups. Governor limit: 100 callouts per transaction — do NOT enqueue this job
 *   with more than 100 Contact Ids at once.
 * - If API returns an error or no match, the target field is left null on purpose
 *   (design decision: we prefer "no data" to "bad data").
 */
public with sharing class NationalizeService implements Queueable, Database.AllowsCallouts {

    // Accepting List<Id> instead of List<Contact> keeps the serialised payload small
    // (critical for Queueable, which has a heap limit for serialised state).
    private List<Id> contactIds;

    /**
     * @param contactIds Ids of Contact records to enrich. Caller must ensure none have
     *                   a null/blank FirstName; this class re-filters defensively but
     *                   callers should not rely on that.
     */
    public NationalizeService(List<Id> contactIds) {
        this.contactIds = contactIds;
    }

    /**
     * Queueable entry point. Executes in an async transaction after the initiating
     * trigger has committed.
     */
    public void execute(QueueableContext ctx) {
        // Re-query in the async context rather than trusting values passed in from
        // the synchronous transaction. Field values could have been changed by other
        // triggers or processes between enqueue time and execution time.
        // The `FirstName != null` filter is belt-and-braces; the handler already
        // enforces it, but defending here makes the class safe to call from anywhere.
        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE Id IN :contactIds AND FirstName != null
        ];

        // If nothing survived the re-query (e.g. all contacts were deleted between
        // enqueue and execute), exit early to save the callout + DML work.
        if (contacts.isEmpty()) {
            return;
        }

        // Build the code -> name lookup once, outside the loop. This avoids a repeated
        // describe call for every contact (describe is cheap but not free).
        Map<String, String> countryMap = getCountryCodeMap();

        // Accumulate updates into a list; we'll DML them together at the end
        // to stay within the 150-DML-statements-per-transaction governor limit.
        List<Contact> toUpdate = new List<Contact>();

        for (Contact c : contacts) {
            // One HTTP callout per contact. If this loop ever handles more than ~90
            // contacts, revisit the design — we're close to the 100-callout ceiling.
            String countryCode = getCountryForName(c.FirstName);

            // Null means either the API errored OR returned an empty prediction list.
            // In both cases we skip the update so Nationalized_Country__c stays null,
            // signalling "no reliable answer".
            if (countryCode != null) {
                // Salesforce's picklist may not have every country code Nationalize.io
                // returns. If the lookup misses, fall back to just the code so we
                // never lose the information entirely.
                String countryName = countryMap.get(countryCode);
                String displayValue = countryName != null
                    ? countryCode + ', ' + countryName
                    : countryCode;

                // Use Id-only constructor instead of re-fetching the full record.
                // This keeps the heap small and the update statement lean.
                toUpdate.add(new Contact(
                    Id = c.Id,
                    Nationalized_Country__c = displayValue
                ));
            }
        }

        // Single DML for the whole batch. Note: this is an all-or-nothing update;
        // if ANY contact fails validation, the entire job rolls back.
        // If partial-success semantics are needed in the future, swap to
        // Database.update(toUpdate, false) and log the per-row errors.
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    /**
     * Builds a map of ISO country code -> country label from Salesforce's built-in
     * Contact.MailingCountryCode picklist. We reuse this standard list so we don't
     * have to maintain our own hardcoded country table.
     *
     * Note: requires the org to have State & Country Picklists enabled (which is
     * the default for new orgs). If the picklist is disabled, this returns an empty
     * map and the service will gracefully fall back to writing just the code.
     */
    @TestVisible
    private static Map<String, String> getCountryCodeMap() {
        Map<String, String> codeToName = new Map<String, String>();

        // getDescribe() is safe to call inside triggers/queueables; it does not
        // consume SOQL or DML limits.
        List<Schema.PicklistEntry> entries = Contact.MailingCountryCode.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry entry : entries) {
            // entry.getValue() = 'BD', entry.getLabel() = 'Bangladesh'
            codeToName.put(entry.getValue(), entry.getLabel());
        }
        return codeToName;
    }

    /**
     * Performs a single HTTP GET to Nationalize.io for the given first name and
     * returns the country_id with the highest probability, or null on any failure.
     *
     * Why null instead of throwing?
     * - One bad name should not abort the entire batch. Swallowing the error here
     *   means the caller can still update the other contacts successfully.
     * - Errors ARE logged at ERROR level so they remain visible in debug logs /
     *   log-based alerting.
     */
    @TestVisible
    private static String getCountryForName(String firstName) {
        HttpRequest req = new HttpRequest();
        // URL-encode the name so it survives special characters (spaces, diacritics,
        // non-latin scripts). Without this, a name like "Jo Ann" would break the URL.
        req.setEndpoint('https://api.nationalize.io/?name=' + EncodingUtil.urlEncode(firstName, 'UTF-8'));
        req.setMethod('GET');
        // 10s timeout is a balance between "don't hang the job" and "give a slow
        // external API a reasonable chance". Apex max timeout is 120_000 ms (2 min).
        req.setTimeout(10000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);

            // Anything other than 200 is treated as a failure: rate limiting (429),
            // server errors (5xx), or client errors (4xx) all return null.
            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.ERROR,
                    'Nationalize API non-200 response for name="' + firstName +
                    '". Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
                return null;
            }

            return parseCountry(res.getBody());
        } catch (Exception e) {
            // Catches CalloutException (DNS, timeout, SSL) and any parsing exceptions
            // bubbling up. We intentionally catch the base Exception here because
            // *any* failure at this point should result in the same behaviour: skip.
            System.debug(LoggingLevel.ERROR,
                'Nationalize API callout failed for name="' + firstName + '": ' + e.getMessage());
            return null;
        }
    }

    /**
     * Parses the Nationalize.io JSON body and returns the country_id with the
     * highest probability. Returns null if the response has no countries.
     *
     * Expected JSON shape (simplified):
     *   { "name":"ali", "country":[
     *       {"country_id":"TR","probability":0.85},
     *       {"country_id":"AZ","probability":0.10}
     *   ]}
     *
     * TestVisible so the unit test can invoke it directly without mocking HTTP.
     */
    @TestVisible
    private static String parseCountry(String jsonBody) {
        // deserializeUntyped is chosen over a strongly-typed class so we're not forced
        // to maintain a wrapper DTO just for a 3-field response.
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> countries = (List<Object>) result.get('country');

        // The API returns an empty array when it cannot predict a country for a name.
        // We treat that as a soft miss, not an error.
        if (countries == null || countries.isEmpty()) {
            return null;
        }

        // Walk the array once, tracking the max-probability entry. O(n) where n is
        // typically <= 5, so no need to sort.
        String bestCountry = null;
        Decimal bestProb = 0;

        for (Object obj : countries) {
            Map<String, Object> entry = (Map<String, Object>) obj;
            String countryId = (String) entry.get('country_id');
            // probability is a JSON number; deserializeUntyped gives us Decimal here.
            Decimal probability = (Decimal) entry.get('probability');

            // Strict greater-than means that if two countries somehow share the same
            // probability, we keep the first one — deterministic and easy to reason about.
            if (probability > bestProb) {
                bestProb = probability;
                bestCountry = countryId;
            }
        }

        return bestCountry;
    }
}
