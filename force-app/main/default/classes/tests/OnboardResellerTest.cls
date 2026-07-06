@isTest
private class OnboardResellerTest {

    private static OnboardReseller.Request makeRequest(String name, Decimal amount) {
        OnboardReseller.Request req = new OnboardReseller.Request();
        req.resellerName = name;
        req.dealAmount = amount;
        return req;
    }

    @isTest
    static void onboardsPlatinumTier() {
        Test.startTest();
        List<OnboardReseller.Result> results = OnboardReseller.onboard(
            new List<OnboardReseller.Request>{ makeRequest('Platinum Partner', 60000) }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        OnboardReseller.Result res = results[0];
        System.assertEquals('Platinum', res.tier, 'deal >= 50000 -> Platinum');
        System.assertEquals('15%', res.commissionRate);
        System.assertNotEquals(null, res.accountId, 'account created');
        System.assertNotEquals(null, res.contactId, 'contact created');
        System.assertNotEquals(null, res.opportunityId, 'opportunity created');
        System.assert(res.summary.contains('Platinum'), 'summary reflects tier');

        // Verify the Opportunity was persisted with the platinum stage + amount
        Opportunity opp = [SELECT StageName, Amount FROM Opportunity WHERE Id = :res.opportunityId];
        System.assertEquals('Negotiation/Review', opp.StageName);
        System.assertEquals(60000, opp.Amount);
    }

    @isTest
    static void onboardsGoldTier() {
        Test.startTest();
        List<OnboardReseller.Result> results = OnboardReseller.onboard(
            new List<OnboardReseller.Request>{ makeRequest('Gold Partner', 25000) }
        );
        Test.stopTest();

        OnboardReseller.Result res = results[0];
        System.assertEquals('Gold', res.tier, 'deal >= 20000 -> Gold');
        System.assertEquals('10%', res.commissionRate);

        Opportunity opp = [SELECT StageName FROM Opportunity WHERE Id = :res.opportunityId];
        System.assertEquals('Proposal/Price Quote', opp.StageName);
    }

    @isTest
    static void onboardsSilverTier() {
        Test.startTest();
        List<OnboardReseller.Result> results = OnboardReseller.onboard(
            new List<OnboardReseller.Request>{ makeRequest('Silver Partner', 5000) }
        );
        Test.stopTest();

        OnboardReseller.Result res = results[0];
        System.assertEquals('Silver', res.tier, 'deal < 20000 -> Silver');
        System.assertEquals('5%', res.commissionRate);

        Opportunity opp = [SELECT StageName FROM Opportunity WHERE Id = :res.opportunityId];
        System.assertEquals('Prospecting', opp.StageName);
    }

    @isTest
    static void reusesExistingAccount() {
        Account existing = new Account(Name = 'Existing Partner');
        insert existing;

        Test.startTest();
        List<OnboardReseller.Result> results = OnboardReseller.onboard(
            new List<OnboardReseller.Request>{ makeRequest('Existing Partner', 30000) }
        );
        Test.stopTest();

        OnboardReseller.Result res = results[0];
        System.assertEquals(existing.Id, res.accountId, 'existing account reused, not duplicated');

        Integer accCount = [SELECT COUNT() FROM Account WHERE Name = 'Existing Partner'];
        System.assertEquals(1, accCount, 'no duplicate account created');
    }

    @isTest
    static void onboardsMultipleRequestsInBulk() {
        Test.startTest();
        List<OnboardReseller.Result> results = OnboardReseller.onboard(
            new List<OnboardReseller.Request>{
                makeRequest('Bulk A', 70000),
                makeRequest('Bulk B', 21000),
                makeRequest('Bulk C', 1000)
            }
        );
        Test.stopTest();

        System.assertEquals(3, results.size(), 'one result per request');
        System.assertEquals('Platinum', results[0].tier);
        System.assertEquals('Gold', results[1].tier);
        System.assertEquals('Silver', results[2].tier);
    }
}
