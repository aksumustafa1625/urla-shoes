/**
 * Tests for UrlaInterviewPrepNotion.
 *
 * Every publishX() method delegates to NotionPublisher.publish(...), which
 * makes one HTTP callout to https://api.notion.com/v1/pages. A single
 * HttpCalloutMock returning 200 covers every callout, so driving publishAll()
 * plus the one method not in it (publishComplianceCockpit) executes all nine
 * static StarEntry builders — the bulk of the 329 lines — cheaply.
 *
 * Notion_Config__c is seeded (Token__c + Parent_Page_Id__c) so NotionPublisher
 * clears its config guard and proceeds to the callout. Mock is registered
 * BEFORE Test.startTest()/the callout to avoid "uncommitted work pending".
 */
@isTest
private class UrlaInterviewPrepNotionTest {

    private static void seedNotionConfig() {
        Notion_Config__c cfg = new Notion_Config__c(
            Token__c = 'secret_test_token',
            Parent_Page_Id__c = '11111111111111111111111111111111'
        );
        insert cfg;
    }

    /** Returns a Notion-shaped 200 for any /v1/pages POST. */
    private class NotionSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"id":"page123","url":"https://www.notion.so/page123"}');
            return res;
        }
    }

    @isTest
    static void publishAllPublishesEveryFeature() {
        seedNotionConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        Test.startTest();
        List<NotionPublisher.PublishResult> results = UrlaInterviewPrepNotion.publishAll();
        Test.stopTest();

        System.assertEquals(8, results.size(), 'publishAll should publish the 8 core features');
        for (NotionPublisher.PublishResult r : results) {
            System.assertEquals(true, r.success, 'each publish should succeed under the mock');
            System.assertEquals('page123', r.notionPageId);
        }
    }

    @isTest
    static void publishComplianceCockpitPublishes() {
        // The 9th feature builder is not part of publishAll — cover it directly.
        seedNotionConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        Test.startTest();
        NotionPublisher.PublishResult r = UrlaInterviewPrepNotion.publishComplianceCockpit();
        Test.stopTest();

        System.assertEquals(true, r.success);
        System.assertEquals(200, r.statusCode);
        System.assertEquals('page123', r.notionPageId);
    }

    @isTest
    static void individualPublishersEachReturnSuccess() {
        // Drives the remaining single-entry publisher wrappers explicitly so
        // each public method is covered even in isolation.
        seedNotionConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        Test.startTest();
        System.assertEquals(true, UrlaInterviewPrepNotion.publishRouteWeather().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishNationalization().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishLoanCreation().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishResellerMatching().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishLeadQueue().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishTierBadge().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishTaskAggregation().success);
        System.assertEquals(true, UrlaInterviewPrepNotion.publishFileHub().success);
        Test.stopTest();
    }
}
