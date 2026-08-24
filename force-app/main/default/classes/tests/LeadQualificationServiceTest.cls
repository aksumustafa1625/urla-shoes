/**
 * @description : Unit tests for LeadQualificationService (Agentforce/MCP invocable
 *                "Qualify and Route Lead"). Covers scoring branches (DACH bonus +
 *                budget tiers), Hot/Warm/Cold rating, Hot-lead task creation, default
 *                naming fallbacks and the summary string.
 *
 * Design notes (why the previous org-only version failed and how this fixes it):
 *   1. SOQL 101 — qualifyAndRoute() does `insert ld` INSIDE its per-request loop, so
 *      every inserted Lead fires LeadTrigger -> LeadShiftTriggerHandler.afterInsert ->
 *      LeadQueueService.processNewLeads -> ShiftSelector.getActiveShifts (a SOQL query).
 *      Inserting many leads (or one-by-one) multiplied that SOQL past 100. Here we
 *      bypass the intake handler via TriggerHandler.bypass('LeadShiftTriggerHandler')
 *      so the queue-intake chain never runs, and keep request batches tiny. The single
 *      qualify call is wrapped in Test.startTest()/stopTest().
 *   2. FIELD_INTEGRITY [Country] — State/Country picklists are enabled on this org, so
 *      the Lead.Country text field only accepts valid integration values. We use full
 *      names ('Germany', 'Austria', 'Switzerland', 'France') which are valid AND satisfy
 *      the service's DACH scoring logic (it lower-cases and matches germany/austria/...).
 *
 * @group : Lead Qualification
 */
@IsTest
private class LeadQualificationServiceTest {

    // Suppress the shift-queue intake trigger for every lead insert the service does.
    // The service under test is unrelated to queue routing; bypassing keeps the whole
    // transaction well under the 100-SOQL limit.
    private static void bypassIntake() {
        TriggerHandler.bypass('LeadShiftTriggerHandler');
    }

    private static LeadQualificationService.Request buildRequest(
        String firstName, String lastName, String company, Decimal budget, String country) {
        LeadQualificationService.Request req = new LeadQualificationService.Request();
        req.leadFirstName = firstName;
        req.leadLastName  = lastName;
        req.companyName   = company;
        req.budget        = budget;
        req.country       = country;
        return req;
    }

    @IsTest
    static void hotLead_dachAndHighBudget_createsTask() {
        bypassIntake();

        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('Hans', 'Muller', 'Berlin Retail GmbH', 60000, 'Germany')
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        LeadQualificationService.Response res = results[0];

        // DACH (+40) + budget >= 50000 (+50) = 90 -> Hot
        System.assertEquals(90, res.leadScore, 'Germany + 60k budget should score 90.');
        System.assertEquals('Hot', res.rating);
        System.assertEquals(true, res.taskCreated, 'Hot leads must create a follow-up task.');
        System.assertNotEquals(null, res.leadId);
        System.assert(res.summary.contains('Call within 24h'),
            'Hot summary should recommend the 24h call. Got: ' + res.summary);

        Lead ld = [SELECT Rating, Country, AnnualRevenue FROM Lead WHERE Id = :res.leadId];
        System.assertEquals('Hot', ld.Rating);
        System.assertEquals(60000, ld.AnnualRevenue);

        System.assertEquals(1,
            [SELECT COUNT() FROM Task WHERE WhoId = :res.leadId AND Priority = 'High'],
            'Exactly one high-priority task for the Hot lead.');
    }

    @IsTest
    static void warmLead_dachAndMidBudget_noTask() {
        bypassIntake();

        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('Anna', 'Gruber', 'Wien Shoes AG', 25000, 'Austria')
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        LeadQualificationService.Response res = results[0];
        // DACH (+40) + budget >= 20000 (+25) = 65 -> Warm
        System.assertEquals(65, res.leadScore, 'Austria + 25k budget should score 65.');
        System.assertEquals('Warm', res.rating);
        System.assertEquals(false, res.taskCreated, 'Warm leads must NOT create a task.');
        System.assert(res.summary.contains('Follow up this week'),
            'Warm summary should recommend a weekly follow up. Got: ' + res.summary);

        System.assertEquals(0,
            [SELECT COUNT() FROM Task WHERE WhoId = :res.leadId],
            'No task for a Warm lead.');
    }

    @IsTest
    static void warmLead_dachLowBudget_scoresFifty() {
        bypassIntake();

        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('Urs', 'Meier', 'Zurich Kicks', 5000, 'Switzerland')
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        LeadQualificationService.Response res = results[0];
        // DACH (+40) + budget < 20000 (+10) = 50 -> Warm (boundary at 40..69)
        System.assertEquals(50, res.leadScore, 'Switzerland + 5k budget should score 50.');
        System.assertEquals('Warm', res.rating);
        System.assertEquals(false, res.taskCreated);
    }

    @IsTest
    static void coldLead_nonDachLowBudget_addsToNurture() {
        bypassIntake();

        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('Marie', 'Dubois', 'Paris Distribution', 5000, 'France')
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        LeadQualificationService.Response res = results[0];
        // non-DACH (0) + budget < 20000 (+10) = 10 -> Cold
        System.assertEquals(10, res.leadScore, 'France + 5k budget should score 10.');
        System.assertEquals('Cold', res.rating);
        System.assertEquals(false, res.taskCreated);
        System.assert(res.summary.contains('nurture campaign'),
            'Cold summary should recommend a nurture campaign. Got: ' + res.summary);
    }

    @IsTest
    static void nonDachHighBudget_scoresFiftyWarm() {
        bypassIntake();

        // Exercises the non-DACH path (no +40) together with the >= 50000 tier (+50)
        // and a null country (summary 'N/A' branch + no FIELD_INTEGRITY risk).
        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('John', 'Smith', 'NYC Footwear', 80000, null)
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        LeadQualificationService.Response res = results[0];
        System.assertEquals(50, res.leadScore, 'No country + 80k budget should score 50.');
        System.assertEquals('Warm', res.rating);
        System.assert(res.summary.contains('N/A'),
            'Null country should render as N/A in summary. Got: ' + res.summary);
    }

    @IsTest
    static void blankNamesAndNullBudget_defaultsApplied() {
        bypassIntake();

        // Blank last name / company -> 'Unknown'; null budget -> +10 (lowest tier).
        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest(null, '', '', null, 'France')
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        LeadQualificationService.Response res = results[0];
        System.assertEquals(10, res.leadScore, 'No DACH + null budget -> 10.');
        System.assertEquals('Cold', res.rating);

        Lead ld = [SELECT LastName, Company FROM Lead WHERE Id = :res.leadId];
        System.assertEquals('Unknown', ld.LastName, 'Blank last name defaults to Unknown.');
        System.assertEquals('Unknown', ld.Company, 'Blank company defaults to Unknown.');
    }

    @IsTest
    static void bulkRequests_singleCall_allProcessed() {
        bypassIntake();

        // Small batch (well under 100 SOQL even if intake ran) processed in one call.
        List<LeadQualificationService.Request> reqs =
            new List<LeadQualificationService.Request>{
                buildRequest('A', 'One',   'Co A', 60000, 'Germany'),      // Hot
                buildRequest('B', 'Two',   'Co B', 25000, 'Austria'),      // Warm
                buildRequest('C', 'Three', 'Co C', 5000,  'France')        // Cold
            };

        Test.startTest();
        List<LeadQualificationService.Response> results =
            LeadQualificationService.qualifyAndRoute(reqs);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'All three requests should return a response.');
        System.assertEquals('Hot',  results[0].rating);
        System.assertEquals('Warm', results[1].rating);
        System.assertEquals('Cold', results[2].rating);

        System.assertEquals(3, [SELECT COUNT() FROM Lead
            WHERE Company IN ('Co A', 'Co B', 'Co C')],
            'Three Lead records should be created.');
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE Priority = 'High'],
            'Only the single Hot lead creates a task.');
    }
}
