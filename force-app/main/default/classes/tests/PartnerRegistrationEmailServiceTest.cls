/**
 * Tests for PartnerRegistrationEmailService.
 *
 * This service does NOT make an HTTP callout — it only queries/updates
 * Reseller_Match_Log__c and sends an email. Email dispatch is guarded by
 * `if (!Test.isRunningTest())`, so no email is actually sent under test and
 * no HttpCalloutMock is required. We exercise the dedup check and the token
 * generation / log-update path, plus the "no log found" early return.
 */
@isTest
private class PartnerRegistrationEmailServiceTest {

    private static Reseller_Match_Log__c makeLog(String email, String domain, Boolean emailSent) {
        Reseller_Match_Log__c log = new Reseller_Match_Log__c(
            Incoming_Email__c = email,
            Extracted_Domain__c = domain,
            Registration_Email_Sent__c = emailSent
        );
        insert log;
        return log;
    }

    @isTest
    static void shouldSendReturnsTrueWhenNoPriorEmail() {
        // A log exists for the domain, but no registration email has been sent yet.
        makeLog('lead@acme.com', 'acme.com', false);

        Test.startTest();
        Boolean shouldSend = PartnerRegistrationEmailService.shouldSendRegistrationEmail('acme.com');
        Test.stopTest();

        System.assertEquals(true, shouldSend,
            'no prior sent email for this domain -> should send');
    }

    @isTest
    static void shouldSendReturnsFalseWhenAlreadySent() {
        makeLog('lead@acme.com', 'acme.com', true);

        Test.startTest();
        Boolean shouldSend = PartnerRegistrationEmailService.shouldSendRegistrationEmail('acme.com');
        Test.stopTest();

        System.assertEquals(false, shouldSend,
            'an email already went out for this domain -> should NOT send again');
    }

    @isTest
    static void shouldSendReturnsTrueForUnknownDomain() {
        Test.startTest();
        Boolean shouldSend = PartnerRegistrationEmailService.shouldSendRegistrationEmail('nowhere.com');
        Test.stopTest();

        System.assertEquals(true, shouldSend, 'no log at all -> should send');
    }

    @isTest
    static void sendRegistrationEmailUpdatesLogWithToken() {
        Reseller_Match_Log__c log = makeLog('partner@urla-demo.com', 'urla-demo.com', false);

        Test.startTest();
        PartnerRegistrationEmailService.sendRegistrationEmail('partner@urla-demo.com');
        Test.stopTest();

        Reseller_Match_Log__c updated = [
            SELECT Verification_Token__c, Token_Used__c, Token_Expiration__c, Registration_Email_Sent__c
            FROM Reseller_Match_Log__c
            WHERE Id = :log.Id
        ];
        System.assert(String.isNotBlank(updated.Verification_Token__c),
            'a verification token should be generated');
        System.assertEquals(false, updated.Token_Used__c, 'new token starts unused');
        System.assertEquals(true, updated.Registration_Email_Sent__c,
            'the log should be marked as email-sent');
        System.assertNotEquals(null, updated.Token_Expiration__c,
            'an expiration should be set');
    }

    @isTest
    static void sendRegistrationEmailNoMatchingLogIsNoOp() {
        // No log for this email — the method should log a debug and return without error.
        Test.startTest();
        PartnerRegistrationEmailService.sendRegistrationEmail('ghost@no-log.com');
        Test.stopTest();

        System.assertEquals(0,
            [SELECT COUNT() FROM Reseller_Match_Log__c WHERE Incoming_Email__c = 'ghost@no-log.com'],
            'no log should have been created or updated');
    }
}
