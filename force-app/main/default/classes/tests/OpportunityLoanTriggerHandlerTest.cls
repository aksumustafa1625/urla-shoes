/**
 * @description : Unit tests for the Closed-Won -> Loan__c creation + sync flow:
 *                OpportunityLoanTriggerHandler + LoanCreationService + LoanSyncService v2
 *                + LoanSyncRetryScheduler + Loan_Sync_Log__c audit trail.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 */
@IsTest
private class OpportunityLoanTriggerHandlerTest {

    private static Id createAccount() {
        return OpportunityTestDataFactory.createAccount(true).Id;
    }

    @IsTest
    static void closedWonOnInsert_plainTextSuccess_syncsWithOkMarker() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));

        Test.startTest();
        insert new Opportunity(
            Name = 'Insert-at-Won', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 150000, Term_In_Months__c = 48
        );
        Test.stopTest();

        Loan__c loan = [
            SELECT Loan_Amount__c, Monthly_Payments__c, isSynced__c,
                   Core_System_Ref__c, Retry_Count__c, Last_Sync_Attempt__c
            FROM Loan__c LIMIT 1
        ];
        System.assertEquals(150000, loan.Loan_Amount__c);
        System.assertEquals(3125.00, loan.Monthly_Payments__c);
        System.assertEquals(true, loan.isSynced__c);
        System.assertEquals('OK', loan.Core_System_Ref__c, 'Plain-text response -> generic OK marker');
        System.assertEquals(0, loan.Retry_Count__c);
        System.assertNotEquals(null, loan.Last_Sync_Attempt__c);

        List<Loan_Sync_Log__c> logs = [SELECT Success__c, HTTP_Status__c, Attempt_Number__c FROM Loan_Sync_Log__c];
        System.assertEquals(1, logs.size(), 'One audit log per attempt.');
        System.assertEquals(true, logs[0].Success__c);
        System.assertEquals(200, logs[0].HTTP_Status__c);
        System.assertEquals(1, logs[0].Attempt_Number__c);
    }

    @IsTest
    static void jsonResponse_extractsConfirmationNumber() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS_JSON));

        Test.startTest();
        insert new Opportunity(
            Name = 'JSON-Response', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 120000, Term_In_Months__c = 24
        );
        Test.stopTest();

        Loan__c loan = [SELECT Core_System_Ref__c, isSynced__c FROM Loan__c LIMIT 1];
        System.assertEquals(true, loan.isSynced__c);
        System.assert(loan.Core_System_Ref__c.startsWith('CS-2026-'),
            'Confirmation number should be extracted from JSON response, got: ' + loan.Core_System_Ref__c);
    }

    @IsTest
    static void syncFailure_incrementsRetryCountAndLogsError() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_ERROR));

        Test.startTest();
        insert new Opportunity(
            Name = 'Fail-Sync', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 10000, Term_In_Months__c = 10
        );
        Test.stopTest();

        Loan__c loan = [SELECT isSynced__c, Retry_Count__c, Sync_Error__c FROM Loan__c LIMIT 1];
        System.assertEquals(false, loan.isSynced__c);
        System.assertEquals(1, loan.Retry_Count__c);
        System.assertNotEquals(null, loan.Sync_Error__c);

        List<Loan_Sync_Log__c> logs = [SELECT Success__c, HTTP_Status__c FROM Loan_Sync_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals(false, logs[0].Success__c);
        System.assertEquals(500, logs[0].HTTP_Status__c);
    }

    @IsTest
    static void retryScheduler_pickUpUnsyncedLoansAndSyncs() {
        Id acctId = createAccount();

        // Seed a failure OUTSIDE Test.startTest(): insert triggers a Queueable that
        // runs synchronously in test context only if inside startTest/stopTest.
        // Here we bypass that by creating the Loan directly so we control its state.
        Opportunity opp = new Opportunity(
            Name = 'Retry-Me', StageName = 'Prospecting',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 60000, Term_In_Months__c = 12
        );
        insert opp;

        Loan__c preSeeded = new Loan__c(
            Opportunity__c = opp.Id,
            Loan_Amount__c = 60000,
            Term_In_Months__c = 12,
            Monthly_Payments__c = 5000,
            isSynced__c = false,
            Retry_Count__c = 1,
            Sync_Error__c = 'HTTP 500'
        );
        insert preSeeded;

        // Now run the retry scheduler with a success mock. Only ONE Test.startTest/stopTest
        // pair — Apex allows only one async window per test method.
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));
        Test.startTest();
        LoanSyncRetryScheduler.runRetry();
        Test.stopTest();

        Loan__c loanAfterRetry = [SELECT isSynced__c, Retry_Count__c FROM Loan__c WHERE Id = :preSeeded.Id];
        System.assertEquals(true, loanAfterRetry.isSynced__c);
        System.assertEquals(0, loanAfterRetry.Retry_Count__c, 'Successful retry must reset retry counter.');

        System.assertEquals(1, [SELECT Count() FROM Loan_Sync_Log__c WHERE Loan__c = :preSeeded.Id],
            'One log for the successful retry attempt.');
    }

    @IsTest
    static void auraRetry_enqueuesForSingleLoan() {
        Id acctId = createAccount();

        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_ERROR));
        insert new Opportunity(
            Name = 'Aura-Retry', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 24000, Term_In_Months__c = 12
        );

        Loan__c loan = [SELECT Id FROM Loan__c LIMIT 1];

        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));
        Test.startTest();
        LoanSyncService.retry(loan.Id);
        Test.stopTest();

        System.assertEquals(true, [SELECT isSynced__c FROM Loan__c WHERE Id = :loan.Id].isSynced__c);
    }

    @IsTest
    static void getDashboard_returnsLoanAndLogs() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS_JSON));

        Test.startTest();
        insert new Opportunity(
            Name = 'Dash-Test', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 90000, Term_In_Months__c = 18
        );
        Test.stopTest();

        Loan__c l = [SELECT Id FROM Loan__c LIMIT 1];
        Map<String, Object> dash = LoanSyncService.getDashboard(l.Id);

        System.assertNotEquals(null, dash.get('loan'));
        List<Loan_Sync_Log__c> logs = (List<Loan_Sync_Log__c>) dash.get('logs');
        System.assertEquals(1, logs.size());
        System.assertEquals(5, dash.get('maxRetries'));
    }

    @IsTest
    static void editingAlreadyClosedWonOpp_doesNotCreateDuplicate() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));

        Opportunity opp = new Opportunity(
            Name = 'No-Dup', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 5000, Term_In_Months__c = 5
        );
        insert opp;
        System.assertEquals(1, [SELECT Count() FROM Loan__c WHERE Opportunity__c = :opp.Id]);

        Test.startTest();
        opp.Name = 'No-Dup (renamed)';
        update opp;
        Test.stopTest();

        System.assertEquals(1, [SELECT Count() FROM Loan__c WHERE Opportunity__c = :opp.Id]);
    }

    @IsTest
    static void bulkInsert_oneCalloutAllSynced() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS_JSON));

        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 200; i++) {
            opps.add(new Opportunity(
                Name = 'Bulk ' + i, StageName = 'Closed Won',
                CloseDate = Date.today(), AccountId = acctId,
                Amount = 24000, Term_In_Months__c = 24
            ));
        }

        Test.startTest();
        insert opps;
        Test.stopTest();

        List<Loan__c> loans = [SELECT isSynced__c, Core_System_Ref__c FROM Loan__c];
        System.assertEquals(200, loans.size());
        for (Loan__c l : loans) {
            System.assertEquals(true, l.isSynced__c);
            System.assert(l.Core_System_Ref__c != null && l.Core_System_Ref__c.startsWith('CS-2026-'));
        }
        System.assertEquals(200, [SELECT Count() FROM Loan_Sync_Log__c]);
    }

    @IsTest
    static void nullOrZeroTerm_producesNullMonthlyPayment() {
        Id acctId = createAccount();
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));

        Test.startTest();
        insert new Opportunity(
            Name = 'No-Term', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acctId,
            Amount = 50000, Term_In_Months__c = null
        );
        Test.stopTest();

        Loan__c loan = [SELECT Monthly_Payments__c, Loan_Amount__c FROM Loan__c LIMIT 1];
        System.assertEquals(null, loan.Monthly_Payments__c);
        System.assertEquals(50000, loan.Loan_Amount__c);
    }

    @IsTest
    static void retry_nullId_throwsAuraHandled() {
        try {
            LoanSyncService.retry(null);
            System.assert(false, 'Should have thrown for null loanId');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
