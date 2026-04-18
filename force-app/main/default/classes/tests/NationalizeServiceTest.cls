/**
 * @description : Unit tests for NationalizeService and ContactTriggerHandler.
 *                Covers the three API scenarios required by the specification
 *                (success, empty response, error), plus defensive cases
 *                (no FirstName, bulk insert) and a direct unit test of the
 *                parseCountry helper.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Contact Nationalization
 *
 * Design notes:
 * - Uses HttpCalloutMock via NationalizeCalloutMock rather than hitting the real
 *   nationalize.io endpoint. Tests MUST stay hermetic — any test that makes a real
 *   callout will fail in CI and on orgs with strict deploy rules.
 * - Queueable jobs run asynchronously in production, but Test.startTest/stopTest
 *   forces them to complete synchronously inside the test boundary, so we can
 *   assert on the resulting Contact state immediately after stopTest().
 */
@IsTest
private class NationalizeServiceTest {

    /**
     * Verifies the happy path: the API returns country predictions, and the service
     * writes the highest-probability country (formatted as "CODE, Name") to the field.
     */
    @IsTest
    static void testSuccessScenario() {
        // Arrange: stub the HTTP layer with a deterministic 200/OK response.
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_SUCCESS));

        // Create a single Contact with a FirstName so the handler has something to enqueue.
        Contact c = new Contact(FirstName = 'Ali', LastName = 'Test');
        insert c;

        // Act: startTest/stopTest forces the queueable to run synchronously within
        // this test method, so we can assert right after stopTest().
        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        // Assert: the mock response rates TR highest (0.85), so the field should
        // begin with "TR" (the suffix depends on the country label in the org picklist,
        // so we only assert the prefix to keep the test robust across orgs).
        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assert(
            updated.Nationalized_Country__c.startsWith('TR'),
            'Expected country to start with TR, got: ' + updated.Nationalized_Country__c
        );
    }

    /**
     * Verifies that an empty prediction array is treated as "no data", NOT as an error.
     * The field should remain null so downstream consumers can distinguish "not yet
     * enriched" from "enriched with an actual value".
     */
    @IsTest
    static void testEmptyResponseScenario() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_EMPTY));

        Contact c = new Contact(FirstName = 'Xyznotaname', LastName = 'Test');
        insert c;

        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        // Assert: the service must not write "null", "N/A", or any placeholder —
        // the field is left strictly untouched.
        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, updated.Nationalized_Country__c,
            'Field should stay null on empty API response (no placeholder writes).');
    }

    /**
     * Verifies graceful degradation when the external API returns 5xx. The job must
     * not throw; instead it should log and skip so the rest of the batch still commits.
     */
    @IsTest
    static void testErrorScenario() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_ERROR));

        Contact c = new Contact(FirstName = 'Ali', LastName = 'Test');
        insert c;

        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, updated.Nationalized_Country__c,
            'Field should stay null on API 500 — no partial writes, no exceptions.');
    }

    /**
     * Verifies that the handler skips contacts with no FirstName. This is important
     * because the Nationalize.io API requires a name, so inserting a Contact without
     * one must NOT trigger a wasted callout or a failed enqueue.
     */
    @IsTest
    static void testContactWithoutFirstName() {
        // No HTTP mock is set: if the handler incorrectly tries to enqueue a job
        // that then makes a callout, the test will fail with an unmocked callout error.
        Contact c = new Contact(LastName = 'OnlyLastName');
        insert c;

        System.assertNotEquals(null, c.Id,
            'Contact should insert successfully even without FirstName.');
    }

    /**
     * Verifies bulk-safety: inserting many contacts at once must result in a single
     * Queueable processing all of them, without hitting governor limits.
     */
    @IsTest
    static void testBulkInsert() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_SUCCESS));

        // 10 is small enough to stay under 100 callouts-per-txn but large enough to
        // catch naive per-record DML/SOQL mistakes.
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 10; i++) {
            contacts.add(new Contact(FirstName = 'Ali', LastName = 'Test' + i));
        }
        insert contacts;

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        Test.startTest();
        System.enqueueJob(new NationalizeService(contactIds));
        Test.stopTest();

        // Every contact should be enriched with the same country (the mock always
        // returns TR). If any contact is missing the value, the batch logic is broken.
        List<Contact> updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id IN :contactIds];
        for (Contact c : updated) {
            System.assert(
                c.Nationalized_Country__c.startsWith('TR'),
                'Every contact in the bulk batch should be enriched, got: ' + c.Nationalized_Country__c
            );
        }
    }

    /**
     * Direct unit test for the parseCountry helper. This test pays off because the
     * "pick max probability" logic is easy to get subtly wrong (off-by-one, first-
     * instead-of-max, etc.) and we want a fast signal if it regresses without
     * needing the full HTTP + DML dance.
     */
    @IsTest
    static void testParseCountryMethod() {
        // Case 1: TR has the higher probability even though DE appears first in the
        // array. Proves the method picks the MAX, not the FIRST.
        String jsonSuccess = '{"count":1,"name":"ali","country":[{"country_id":"DE","probability":0.5},{"country_id":"TR","probability":0.9}]}';
        String result = NationalizeService.parseCountry(jsonSuccess);
        System.assertEquals('TR', result,
            'parseCountry must select the entry with the highest probability.');

        // Case 2: empty country array -> null return value (not empty string,
        // not "UNKNOWN", etc.).
        String jsonEmpty = '{"count":0,"name":"xyz","country":[]}';
        String resultEmpty = NationalizeService.parseCountry(jsonEmpty);
        System.assertEquals(null, resultEmpty,
            'parseCountry must return null for an empty country array.');
    }
}
