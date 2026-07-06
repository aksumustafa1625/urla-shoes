/**
 * @description : Unit tests for the Reseller matching cluster:
 *                OpportunityResellerTriggerHandler + ResellerMatchingEngine
 *                + ResellerMatchLogService + ResellerMappingSelector
 *                + ResellerReconciliationService.
 *
 *                Flow under test:
 *                  Opportunity insert/update
 *                    -> OpportunityResellerTriggerHandler (before/after)
 *                    -> ResellerMatchingEngine.matchBefore  (email then domain fallback)
 *                    -> ResellerMappingSelector.getMappings  (SOQL)
 *                    -> ResellerMatchLogService.createLogsAfter (unmatched diagnostics)
 *                  ResellerReconciliationService.reconcile   (invocable back-fill)
 *
 * @author      : Mustafa Aksu
 * @date        : 2026-07-06
 * @group       : Reseller Matching
 */
@IsTest
private class ResellerClusterTest {

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static Id acct() {
        return OpportunityTestDataFactory.createAccount(true).Id;
    }

    private static Reseller__c reseller(String name, String companyEmail) {
        Reseller__c r = new Reseller__c(
            Name = name,
            Company_Email__c = companyEmail
        );
        insert r;
        return r;
    }

    private static Reseller_Mapping__c mapping(String type, String value, Id resellerId) {
        Reseller_Mapping__c m = new Reseller_Mapping__c(
            Mapping_Type__c = type,
            Value__c        = value,
            Reseller__c     = resellerId,
            Is_Active__c    = true,
            Priority__c     = 1
        );
        insert m;
        return m;
    }

    private static Opportunity requery(Id oppId) {
        return [
            SELECT Id, Reseller__c, Reseller_Email__c, Matched_By__c
            FROM Opportunity
            WHERE Id = :oppId
        ];
    }

    // ------------------------------------------------------------------
    // Engine: exact email match
    // ------------------------------------------------------------------

    @IsTest
    static void matchByEmail_populatesResellerNoLog() {
        Id acctId = acct();
        Reseller__c r = reseller('Bursa Reseller', 'partner@bursa.com');
        mapping('Email', 'partner@bursa.com', r.Id);

        Test.startTest();
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'Partner@Bursa.com', true // mixed case -> normalization must still match
        );
        Test.stopTest();

        Opportunity after = requery(opp.Id);
        System.assertEquals(r.Id, after.Reseller__c, 'Exact email mapping should resolve the reseller.');
        System.assertEquals('Email', after.Matched_By__c, 'Match should be attributed to Email.');
        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'A matched opportunity must not create a diagnostic log.');
    }

    // ------------------------------------------------------------------
    // Engine: domain fallback match
    // ------------------------------------------------------------------

    @IsTest
    static void matchByDomain_fallbackPopulatesReseller() {
        Id acctId = acct();
        Reseller__c r = reseller('Bursa Reseller', 'info@bursa.com');
        // Only a DOMAIN mapping exists, no exact email mapping.
        mapping('Domain', 'bursa.com', r.Id);

        Test.startTest();
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'someone.new@bursa.com', true
        );
        Test.stopTest();

        Opportunity after = requery(opp.Id);
        System.assertEquals(r.Id, after.Reseller__c, 'Domain fallback should resolve the reseller.');
        System.assertEquals('Domain', after.Matched_By__c, 'Match should be attributed to Domain.');
        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'A domain-matched opportunity must not create a log.');
    }

    // ------------------------------------------------------------------
    // Log service: no mapping -> "No Mapping Found"
    // ------------------------------------------------------------------

    @IsTest
    static void noMatch_createsLogWithNoneMarker() {
        Id acctId = acct();

        Test.startTest();
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'ghost@unknown-domain.com', true
        );
        Test.stopTest();

        Opportunity after = requery(opp.Id);
        System.assertEquals(null, after.Reseller__c, 'Unmatched opp must have no reseller.');
        System.assertEquals('None', after.Matched_By__c, 'Unmatched opp should be flagged None.');

        List<Reseller_Match_Log__c> logs = [
            SELECT Opportunity__c, Incoming_Email__c, Extracted_Domain__c, Reason__c, Created_From_Trigger__c
            FROM Reseller_Match_Log__c
        ];
        System.assertEquals(1, logs.size(), 'Exactly one diagnostic log for the unmatched opp.');
        System.assertEquals(opp.Id, logs[0].Opportunity__c);
        System.assertEquals('ghost@unknown-domain.com', logs[0].Incoming_Email__c);
        System.assertEquals('unknown-domain.com', logs[0].Extracted_Domain__c);
        System.assertEquals('No Mapping Found', logs[0].Reason__c);
        System.assertEquals(true, logs[0].Created_From_Trigger__c);
    }

    // ------------------------------------------------------------------
    // Log service: null/empty guard + the "Invalid Email" reason branch
    // ------------------------------------------------------------------

    @IsTest
    static void invalidEmailBranch_buildsInvalidEmailReasonButPlatformRejects() {
        Id acctId = acct();

        // Guard clause: null / empty input returns immediately, no work done.
        ResellerMatchLogService.createLogsAfter(null);
        ResellerMatchLogService.createLogsAfter(new List<Opportunity>());

        // Insert a VALID non-matching email (bypass so no auto-log is created), get a real Id.
        TriggerHandler.bypass('OpportunityResellerTriggerHandler');
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'x@nomatch-xyz.com', true
        );
        TriggerHandler.clearBypass('OpportunityResellerTriggerHandler');

        // 'a@' normalizes (contains '@') but extracts a BLANK domain, so the service builds
        // a log with Reason__c = 'Invalid Email'. NOTE: Reseller_Match_Log__c.Incoming_Email__c
        // is itself an Email-format field, so the platform rejects persisting 'a@'. The branch
        // logic still executes (covered) before the insert throws — assert that rejection.
        opp.Reseller_Email__c = 'a@';

        Test.startTest();
        try {
            ResellerMatchLogService.createLogsAfter(new List<Opportunity>{ opp });
            System.assert(false,
                'Expected INVALID_EMAIL_ADDRESS: Incoming_Email__c is an Email-format field.');
        } catch (DmlException e) {
            System.assert(e.getMessage().contains('INVALID_EMAIL_ADDRESS'),
                'Invalid-Email branch runs but the platform rejects the malformed value: '
                + e.getMessage());
        }
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'The rejected insert leaves no persisted log.');
    }

    // ------------------------------------------------------------------
    // Engine + log service: blank / malformed email -> skipped entirely
    // ------------------------------------------------------------------

    @IsTest
    static void blankAndMalformedEmail_noLogNoMatch() {
        Id acctId = acct();

        // 'notanemail' is rejected by the Email-format field at DML, so insert valid
        // emails under bypass, then mutate to the malformed / null cases in memory and
        // drive the engine + log service directly.
        TriggerHandler.bypass('OpportunityResellerTriggerHandler');
        Opportunity malformed = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'valid@somewhere.com', true
        );
        Opportunity blank = OpportunityTestDataFactory.createOpportunity(acctId, true);
        TriggerHandler.clearBypass('OpportunityResellerTriggerHandler');

        // No '@' -> normalizeEmail returns null; null email -> skipped as well.
        malformed.Reseller_Email__c = 'notanemail';
        blank.Reseller_Email__c = null;
        List<Opportunity> opps = new List<Opportunity>{ malformed, blank };

        Test.startTest();
        ResellerMatchingEngine.matchBefore(opps);        // before-context: in-memory only
        ResellerMatchLogService.createLogsAfter(opps);   // after-context: log creation
        Test.stopTest();

        System.assertEquals(null, malformed.Reseller__c, 'Malformed email must not resolve a reseller.');
        System.assertEquals(null, blank.Reseller__c, 'Blank email must not resolve a reseller.');
        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'Malformed / blank emails should not produce diagnostic logs.');
    }

    // ------------------------------------------------------------------
    // Bulk safety: 200 opportunities in a single transaction
    // ------------------------------------------------------------------

    @IsTest
    static void bulkInsert_allMatchedSingleTransaction() {
        Id acctId = acct();
        Reseller__c r = reseller('Test Reseller', 'partner@test.com');
        // Factory bulk opps all carry Reseller_Email__c = 'partner@test.com'.
        mapping('Email', 'partner@test.com', r.Id);

        List<Opportunity> opps = OpportunityTestDataFactory.createBulkOpportunities(acctId, 200);

        Test.startTest();
        insert opps;
        Test.stopTest();

        List<Opportunity> after = [
            SELECT Reseller__c, Matched_By__c FROM Opportunity WHERE Id IN :opps
        ];
        System.assertEquals(200, after.size());
        for (Opportunity o : after) {
            System.assertEquals(r.Id, o.Reseller__c, 'Every bulk opp should resolve to the reseller.');
            System.assertEquals('Email', o.Matched_By__c);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'All matched -> no logs even in bulk.');
    }

    // ------------------------------------------------------------------
    // before/after UPDATE: re-evaluates when a mapping appears later
    // ------------------------------------------------------------------

    @IsTest
    static void update_reMatchesWhenMappingAppears() {
        Id acctId = acct();
        Reseller__c r = reseller('Late Reseller', 'partner@late.com');

        // Insert while unmatched -> creates a log, Matched_By__c = None.
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'partner@late.com', true
        );
        System.assertEquals(null, requery(opp.Id).Reseller__c, 'Precondition: no mapping yet.');
        System.assertEquals(1, [SELECT COUNT() FROM Reseller_Match_Log__c]);

        // Mapping now exists; an update should re-run matching in before-update.
        mapping('Email', 'partner@late.com', r.Id);

        Test.startTest();
        opp.Name = 'Late (updated)';
        update opp;
        Test.stopTest();

        Opportunity after = requery(opp.Id);
        System.assertEquals(r.Id, after.Reseller__c, 'Update should resolve the newly-added mapping.');
        System.assertEquals('Email', after.Matched_By__c);
    }

    // ------------------------------------------------------------------
    // after UPDATE: still unmatched -> no duplicate log, email branch runs
    // ------------------------------------------------------------------

    @IsTest
    static void update_stillUnmatched_noDuplicateLog() {
        Id acctId = acct();

        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'buyer@stillghost.com', true
        );
        System.assertEquals(1, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'Insert of unmatched opp creates one log.');

        Test.startTest();
        opp.Name = 'Ghost (updated)';
        update opp; // exercises afterUpdate email + duplicate-log-prevention branches
        Test.stopTest();

        System.assertEquals(1, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'A second update must not create a duplicate log for the same opp.');
    }

    // ------------------------------------------------------------------
    // Selector: direct coverage of all query methods + empty guards
    // ------------------------------------------------------------------

    @IsTest
    static void selector_directQueries() {
        Id acctId = acct();
        Reseller__c r = reseller('Sel Reseller', 'sel@sel.com');
        mapping('Email',  'sel@sel.com', r.Id);
        mapping('Domain', 'sel.com',     r.Id);

        // Seed a log so getAlreadyLoggedOppIds returns a hit.
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'nolog@nomapping.com', true
        );
        Id loggedOppId = [SELECT Opportunity__c FROM Reseller_Match_Log__c LIMIT 1].Opportunity__c;

        Test.startTest();

        // Empty-set / null guards -> empty maps.
        System.assertEquals(0, ResellerMappingSelector.getMappings('Email', new Set<String>()).size());
        System.assertEquals(0, ResellerMappingSelector.getEmailMappings(null).size());
        System.assertEquals(0, ResellerMappingSelector.getEmailMappings(new Set<String>()).size());
        System.assertEquals(0, ResellerMappingSelector.getDomainMappings(null).size());
        System.assertEquals(0, ResellerMappingSelector.getDomainMappings(new Set<String>()).size());
        System.assertEquals(0, ResellerMappingSelector.getAlreadyLoggedOppIds(new Set<Id>()).size());

        // Populated queries.
        Map<String, Reseller_Mapping__c> emailMap =
            ResellerMappingSelector.getMappings('Email', new Set<String>{ 'sel@sel.com' });
        System.assertEquals(1, emailMap.size());
        System.assertEquals(r.Id, emailMap.get('sel@sel.com').Reseller__c);

        Map<String, Reseller_Mapping__c> emailMap2 =
            ResellerMappingSelector.getEmailMappings(new Set<String>{ 'sel@sel.com' });
        System.assertEquals(1, emailMap2.size());

        Map<String, Reseller_Mapping__c> domainMap =
            ResellerMappingSelector.getDomainMappings(new Set<String>{ 'sel.com' });
        System.assertEquals(1, domainMap.size());
        System.assertEquals(r.Id, domainMap.get('sel.com').Reseller__c);

        Set<Id> logged = ResellerMappingSelector.getAlreadyLoggedOppIds(new Set<Id>{ loggedOppId });
        System.assertEquals(true, logged.contains(loggedOppId),
            'Selector should report the already-logged opportunity.');

        Test.stopTest();
    }

    // ------------------------------------------------------------------
    // Reconciliation: guard clauses (no DML)
    // ------------------------------------------------------------------

    @IsTest
    static void reconcile_guardClauses() {
        Test.startTest();

        // Null input list.
        ResellerReconciliationService.reconcile(null);

        // Empty input list.
        ResellerReconciliationService.reconcile(new List<ResellerReconciliationService.ReconcileInput>());

        // Input with null resellerId.
        ResellerReconciliationService.ReconcileInput nullInput =
            new ResellerReconciliationService.ReconcileInput();
        ResellerReconciliationService.reconcile(
            new List<ResellerReconciliationService.ReconcileInput>{ nullInput }
        );

        // Valid reseller but no matching logs -> logs.isEmpty() early return.
        Reseller__c r = reseller('Lonely Reseller', 'nobody@emptylogs.com');
        ResellerReconciliationService.ReconcileInput emptyLogsInput =
            new ResellerReconciliationService.ReconcileInput();
        emptyLogsInput.resellerId = r.Id;
        ResellerReconciliationService.reconcile(
            new List<ResellerReconciliationService.ReconcileInput>{ emptyLogsInput }
        );

        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'No logs should be created by guard-clause runs.');
    }

    // ------------------------------------------------------------------
    // Reconciliation: happy path back-fills opp + deletes logs
    // ------------------------------------------------------------------

    @IsTest
    static void reconcile_happyPath_assignsResellerAndDeletesLog() {
        Id acctId = acct();
        Reseller__c r = reseller('Kano Reseller', 'partner@kano.com');

        // Unmatched opp on the same domain -> creates a diagnostic log.
        Opportunity opp = OpportunityTestDataFactory.createOpportunityWithResellerEmail(
            acctId, 'buyer@kano.com', true
        );
        System.assertEquals(null, requery(opp.Id).Reseller__c, 'Precondition: unmatched.');
        System.assertEquals(1, [SELECT COUNT() FROM Reseller_Match_Log__c], 'Precondition: one log.');

        ResellerReconciliationService.ReconcileInput input =
            new ResellerReconciliationService.ReconcileInput();
        input.resellerId = r.Id;

        Test.startTest();
        ResellerReconciliationService.reconcile(
            new List<ResellerReconciliationService.ReconcileInput>{ input }
        );
        Test.stopTest();

        System.assertEquals(r.Id, requery(opp.Id).Reseller__c,
            'Reconciliation should back-fill the reseller by domain.');
        System.assertEquals(0, [SELECT COUNT() FROM Reseller_Match_Log__c],
            'Reconciled logs should be deleted.');
    }
}
