/**
 * NationalizeServiceTest
 *
 * Test class for NationalizeService and ContactTriggerHandler.
 * Covers three scenarios:
 * 1. Success - API returns country data, field is updated
 * 2. Empty response - API returns no countries, field stays null
 * 3. Error - API returns 500, field stays null
 */
@IsTest
private class NationalizeServiceTest {

    @IsTest
    static void testSuccessScenario() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_SUCCESS));

        Contact c = new Contact(FirstName = 'Ali', LastName = 'Test');
        insert c;

        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assert(updated.Nationalized_Country__c.startsWith('TR'), 'Should start with TR for name Ali: ' + updated.Nationalized_Country__c);
    }

    @IsTest
    static void testEmptyResponseScenario() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_EMPTY));

        Contact c = new Contact(FirstName = 'Xyznotaname', LastName = 'Test');
        insert c;

        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, updated.Nationalized_Country__c, 'Should remain null when API returns no countries');
    }

    @IsTest
    static void testErrorScenario() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_ERROR));

        Contact c = new Contact(FirstName = 'Ali', LastName = 'Test');
        insert c;

        Test.startTest();
        System.enqueueJob(new NationalizeService(new List<Id>{ c.Id }));
        Test.stopTest();

        Contact updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id = :c.Id];
        System.assertEquals(null, updated.Nationalized_Country__c, 'Should remain null when API returns error');
    }

    @IsTest
    static void testContactWithoutFirstName() {
        // Contact without FirstName should not trigger the service
        Contact c = new Contact(LastName = 'OnlyLastName');
        insert c;

        // No exception should be thrown, handler simply skips contacts without FirstName
        System.assertNotEquals(null, c.Id, 'Contact should be created successfully');
    }

    @IsTest
    static void testBulkInsert() {
        Test.setMock(HttpCalloutMock.class, new NationalizeCalloutMock(NationalizeCalloutMock.SCENARIO_SUCCESS));

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

        List<Contact> updated = [SELECT Nationalized_Country__c FROM Contact WHERE Id IN :contactIds];
        for (Contact c : updated) {
            System.assert(c.Nationalized_Country__c.startsWith('TR'), 'All contacts should start with TR: ' + c.Nationalized_Country__c);
        }
    }

    @IsTest
    static void testParseCountryMethod() {
        // Test the parseCountry method directly
        String jsonSuccess = '{"count":1,"name":"ali","country":[{"country_id":"DE","probability":0.5},{"country_id":"TR","probability":0.9}]}';
        String result = NationalizeService.parseCountry(jsonSuccess);
        System.assertEquals('TR', result, 'Should return the country with highest probability');

        String jsonEmpty = '{"count":0,"name":"xyz","country":[]}';
        String resultEmpty = NationalizeService.parseCountry(jsonEmpty);
        System.assertEquals(null, resultEmpty, 'Should return null for empty country list');
    }
}
