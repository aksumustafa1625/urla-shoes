@isTest
private class NotionPublisherTest {

    private static void seedConfig() {
        Notion_Config__c cfg = new Notion_Config__c(
            Token__c = 'secret_test_token',
            Parent_Page_Id__c = '11111111111111111111111111111111'
        );
        insert cfg;
    }

    private static NotionPublisher.StarEntry sampleEntry() {
        NotionPublisher.StarEntry e = new NotionPublisher.StarEntry();
        e.title = 'Test Entry — Sample Feature';
        e.context = 'Context paragraph.';
        e.problem = 'Problem paragraph.';
        e.goal = 'Goal paragraph.';
        e.constraints = 'Constraints paragraph.';
        e.successCriteria = 'Success criteria paragraph.';
        e.approach = 'Approach paragraph.';
        e.implementation = new List<String>{'step one', 'step two', 'step three'};
        e.codeLanguage = 'apex';
        e.codeSnippet = 'public class Foo { }';
        e.outcome = 'Outcome paragraph.';
        e.tradeOffs = 'Trade-offs paragraph.';
        e.references = new List<String>{'doc one', 'doc two'};
        e.futureWork = 'Future work paragraph.';
        return e;
    }

    private class NotionSuccessMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            System.assertEquals('https://api.notion.com/v1/pages', req.getEndpoint());
            System.assertEquals('POST', req.getMethod());
            System.assertEquals('Bearer secret_test_token', req.getHeader('Authorization'));
            System.assertEquals('2022-06-28', req.getHeader('Notion-Version'));
            System.assert(req.getBody().contains('"title"'), 'page title property should appear in payload');
            System.assert(req.getBody().contains('"type":"toggle"') || req.getBody().contains('"type" : "toggle"'),
                'STAR sections should use plain toggle blocks');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"id":"abc123","url":"https://www.notion.so/abc123"}');
            return res;
        }
    }

    private class NotionFailureMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(401);
            res.setBody('{"object":"error","code":"unauthorized","message":"API token is invalid."}');
            return res;
        }
    }

    @isTest
    static void publishSuccess() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        Test.startTest();
        NotionPublisher.PublishResult result = NotionPublisher.publish(sampleEntry());
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals(200, result.statusCode);
        System.assertEquals('abc123', result.notionPageId);
        System.assertEquals('https://www.notion.so/abc123', result.notionUrl);
    }

    @isTest
    static void publishFailureReturnsErrorBody() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new NotionFailureMock());

        Test.startTest();
        NotionPublisher.PublishResult result = NotionPublisher.publish(sampleEntry());
        Test.stopTest();

        System.assertEquals(false, result.success);
        System.assertEquals(401, result.statusCode);
        System.assert(result.errorBody.contains('unauthorized'));
    }

    @isTest
    static void publishRequiresTitle() {
        seedConfig();
        NotionPublisher.StarEntry empty = new NotionPublisher.StarEntry();
        empty.title = null;
        Boolean threw = false;
        try {
            NotionPublisher.publish(empty);
        } catch (NotionPublisher.NotionPublisherException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('title is required'));
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void publishRequiresConfig() {
        // No config seeded
        Boolean threw = false;
        try {
            NotionPublisher.publish(sampleEntry());
        } catch (NotionPublisher.NotionPublisherException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('not configured'));
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void publishFromJsonSerialization() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        String json = JSON.serialize(sampleEntry());

        Test.startTest();
        NotionPublisher.PublishResult result = NotionPublisher.publishFromJson(json);
        Test.stopTest();

        System.assertEquals(true, result.success);
        System.assertEquals('abc123', result.notionPageId);
    }

    @isTest
    static void longContentIsChunked() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        // Build a >2000-char string to force chunking in richTextChunks
        String longText = '';
        for (Integer i = 0; i < 100; i++) {
            longText += 'abcdefghijklmnopqrstuvwxyz0123456789 ';
        }
        NotionPublisher.StarEntry entry = sampleEntry();
        entry.codeSnippet = longText + longText; // ~7400 chars

        Test.startTest();
        NotionPublisher.PublishResult result = NotionPublisher.publish(entry);
        Test.stopTest();

        System.assertEquals(true, result.success);
    }

    @isTest
    static void optionalSectionsOmitWhenBlank() {
        seedConfig();
        Test.setMock(HttpCalloutMock.class, new NotionSuccessMock());

        NotionPublisher.StarEntry entry = new NotionPublisher.StarEntry();
        entry.title = 'Minimal Entry';
        entry.context = 'just context, nothing else';
        // all other fields left null/empty

        Test.startTest();
        NotionPublisher.PublishResult result = NotionPublisher.publish(entry);
        Test.stopTest();

        System.assertEquals(true, result.success);
    }
}
