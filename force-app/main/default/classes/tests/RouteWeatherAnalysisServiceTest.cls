/**
 * Tests for RouteWeatherAnalysisService.
 *
 * The service calls ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate,
 * which cannot execute against a live Prompt Template inside a test context —
 * it throws a catchable exception that the service swallows, returning an
 * "Analysis unavailable: ..." message. That exercises the full deserialize →
 * buildWeatherString → inputParams → catch path (the only uncovered lines are
 * the success-return branch, which requires a real Einstein response).
 *
 * An HttpCalloutMock is still registered defensively so no "uncommitted work
 * pending" error can surface if the underlying framework attempts a callout,
 * and API_Config__c is seeded to mirror the project's callout-test pattern.
 */
@isTest
private class RouteWeatherAnalysisServiceTest {

    private static void seedApiConfig() {
        API_Config__c cfg = new API_Config__c(
            Google_Maps_Api_Key__c = 'test-google-maps-key',
            OpenWeather_Api_Key__c = 'test-openweather-key'
        );
        insert cfg;
    }

    /** Generic mock — returns a valid JSON body for any endpoint / method. */
    private class GenericJsonMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"generations":[{"text":"Route looks safe."}]}');
            return res;
        }
    }

    private static String sampleWaypointsJson() {
        List<Map<String, Object>> waypoints = new List<Map<String, Object>>{
            new Map<String, Object>{
                'type' => 'START', 'city' => 'Munich', 'temp' => 12,
                'desc' => 'clear sky', 'humidity' => 60, 'wind' => '5 m/s'
            },
            new Map<String, Object>{
                'type' => 'WAYPOINT', 'city' => 'Cologne', 'temp' => 9,
                'desc' => 'light rain', 'humidity' => 82, 'wind' => '7 m/s'
            },
            new Map<String, Object>{
                'type' => 'END', 'city' => 'Berlin', 'temp' => 7,
                'desc' => 'overcast', 'humidity' => 75, 'wind' => '4 m/s'
            }
        };
        return JSON.serialize(waypoints);
    }

    @isTest
    static void analyzeRouteWithValidWaypointsReturnsString() {
        seedApiConfig();
        Test.setMock(HttpCalloutMock.class, new GenericJsonMock());

        Test.startTest();
        String result = RouteWeatherAnalysisService.analyzeRoute(sampleWaypointsJson());
        Test.stopTest();

        // Either a live-style generation or the graceful fallback — never null/blank.
        System.assertNotEquals(null, result, 'analyzeRoute should always return a string');
        System.assert(String.isNotBlank(result), 'result should not be blank');
    }

    @isTest
    static void analyzeRouteWithEmptyListStillReturns() {
        seedApiConfig();
        Test.setMock(HttpCalloutMock.class, new GenericJsonMock());

        Test.startTest();
        String result = RouteWeatherAnalysisService.analyzeRoute('[]');
        Test.stopTest();

        System.assertNotEquals(null, result, 'empty waypoint list should still return a string');
    }

    @isTest
    static void analyzeRouteWithMalformedJsonIsHandledGracefully() {
        seedApiConfig();
        Test.setMock(HttpCalloutMock.class, new GenericJsonMock());

        Test.startTest();
        String result = RouteWeatherAnalysisService.analyzeRoute('this is not json');
        Test.stopTest();

        // Deserialize throws -> caught -> "Analysis unavailable: ..." (never rethrown).
        System.assertNotEquals(null, result, 'malformed JSON must be handled, not rethrown');
        System.assert(result.startsWith('Analysis unavailable'),
            'malformed JSON should return the graceful error message, got: ' + result);
    }
}
