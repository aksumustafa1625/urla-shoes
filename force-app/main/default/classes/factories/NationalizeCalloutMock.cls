/**
 * NationalizeCalloutMock
 *
 * HttpCalloutMock implementation for testing NationalizeService.
 * Supports three scenarios: success, empty response, and error.
 */
@IsTest
public class NationalizeCalloutMock implements HttpCalloutMock {

    private String scenario;

    public static final String SCENARIO_SUCCESS = 'success';
    public static final String SCENARIO_EMPTY = 'empty';
    public static final String SCENARIO_ERROR = 'error';

    public NationalizeCalloutMock(String scenario) {
        this.scenario = scenario;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');

        if (scenario == SCENARIO_SUCCESS) {
            res.setStatusCode(200);
            res.setBody('{"count":1,"name":"ali","country":[{"country_id":"TR","probability":0.85},{"country_id":"AZ","probability":0.10}]}');
        } else if (scenario == SCENARIO_EMPTY) {
            res.setStatusCode(200);
            res.setBody('{"count":0,"name":"xyznotaname","country":[]}');
        } else if (scenario == SCENARIO_ERROR) {
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
        }

        return res;
    }
}
