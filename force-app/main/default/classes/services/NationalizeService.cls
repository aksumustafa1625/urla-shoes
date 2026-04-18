/**
 * NationalizeService
 *
 * Queueable job that calls the Nationalize.io API for each Contact,
 * parses the JSON response, and updates the Nationalized_Country__c field
 * with the most probable country code.
 *
 * Bulk-safe: processes a list of Contact Ids.
 */
public class NationalizeService implements Queueable, Database.AllowsCallouts {

    private List<Id> contactIds;

    public NationalizeService(List<Id> contactIds) {
        this.contactIds = contactIds;
    }

    public void execute(QueueableContext ctx) {
        List<Contact> contacts = [
            SELECT Id, FirstName
            FROM Contact
            WHERE Id IN :contactIds AND FirstName != null
        ];

        List<Contact> toUpdate = new List<Contact>();

        for (Contact c : contacts) {
            String countryCode = getCountryForName(c.FirstName);
            if (countryCode != null) {
                toUpdate.add(new Contact(
                    Id = c.Id,
                    Nationalized_Country__c = countryCode
                ));
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    @TestVisible
    private static String getCountryForName(String firstName) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.nationalize.io/?name=' + EncodingUtil.urlEncode(firstName, 'UTF-8'));
        req.setMethod('GET');
        req.setTimeout(10000);

        try {
            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() != 200) {
                System.debug(LoggingLevel.ERROR, 'Nationalize API error: status=' + res.getStatusCode());
                return null;
            }

            return parseCountry(res.getBody());
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Nationalize API callout failed: ' + e.getMessage());
            return null;
        }
    }

    @TestVisible
    private static String parseCountry(String jsonBody) {
        Map<String, Object> result = (Map<String, Object>) JSON.deserializeUntyped(jsonBody);
        List<Object> countries = (List<Object>) result.get('country');

        if (countries == null || countries.isEmpty()) {
            return null;
        }

        // Find the country with the highest probability
        String bestCountry = null;
        Decimal bestProb = 0;

        for (Object obj : countries) {
            Map<String, Object> entry = (Map<String, Object>) obj;
            String countryId = (String) entry.get('country_id');
            Decimal probability = (Decimal) entry.get('probability');

            if (probability > bestProb) {
                bestProb = probability;
                bestCountry = countryId;
            }
        }

        return bestCountry;
    }
}
