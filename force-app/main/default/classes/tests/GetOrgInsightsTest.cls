@isTest
private class GetOrgInsightsTest {

    @isTest
    static void insightsReturnsPopulatedWrapper() {
        // Account + Reseller so both counts are non-zero
        Account acc = new Account(Name = 'Insights Top Customer');
        insert acc;

        Reseller__c reseller = new Reseller__c(
            Name = 'Insights Reseller',
            Company_Email__c = 'insights@test.com'
        );
        insert reseller;

        // Won opportunity this year (also within the last 2 months) with an Amount
        Opportunity won = new Opportunity(
            Name = 'Won Deal',
            AccountId = acc.Id,
            StageName = 'Closed Won',
            CloseDate = Date.today(),
            Amount = 40000
        );
        insert won;

        // Open opportunity so openPipeline is non-null
        Opportunity open = new Opportunity(
            Name = 'Open Deal',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 15000
        );
        insert open;

        Test.startTest();
        List<GetOrgInsights.Insights> results = GetOrgInsights.getInsights();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'exactly one Insights wrapper returned');
        GetOrgInsights.Insights r = results[0];

        System.assert(r.totalAccounts >= 1, 'at least one account counted');
        System.assert(r.totalResellers >= 1, 'at least one reseller counted');
        System.assert(r.revenueThisYear >= 40000, 'revenue this year includes the won deal');
        System.assert(r.closedWonLast2Months >= 0, 'closed-won last 2 months is non-null');
        System.assert(r.openPipeline >= 15000, 'open pipeline includes the open deal');
        System.assertNotEquals(null, r.topCustomerName, 'top customer name resolved');
        System.assert(r.topCustomerRevenue >= 40000, 'top customer revenue resolved');
        System.assertNotEquals(null, r.summary, 'summary string built');
        System.assert(r.summary.contains('Accounts:'), 'summary contains expected label');
    }

    @isTest
    static void insightsHandlesEmptyOrgGracefully() {
        // No opportunities seeded -> SUM(Amount) returns null and toDecimal coerces to 0.
        Test.startTest();
        List<GetOrgInsights.Insights> results = GetOrgInsights.getInsights();
        Test.stopTest();

        GetOrgInsights.Insights r = results[0];
        System.assertEquals(0, r.closedWonLast2Months, 'null SUM coerced to 0');
        System.assertEquals(0, r.revenueThisYear, 'null SUM coerced to 0');
        System.assertEquals(0, r.openPipeline, 'null SUM coerced to 0');
        System.assertEquals(null, r.topCustomerName, 'no top customer when no won opps');
        System.assertNotEquals(null, r.summary, 'summary still built');
    }
}
