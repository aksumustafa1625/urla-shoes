/**
 * @description : HttpCalloutMock implementation used to simulate responses from the
 *                Nationalize.io API during unit tests. The scenario is passed into
 *                the constructor so a single mock class can cover positive, empty,
 *                and error paths without per-test mock subclasses.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Contact Nationalization
 *
 * Design notes:
 * - Annotated @IsTest so this class does not count against org code size limits
 *   and cannot be invoked from production Apex.
 * - Response bodies mirror the real Nationalize.io JSON structure exactly. If the
 *   upstream contract ever changes, update the bodies here AND in the production
 *   parseCountry tests to catch regressions.
 */
@IsTest
public with sharing class NationalizeCalloutMock implements HttpCalloutMock {

    // Holds the scenario string so `respond()` can branch on it.
    private String scenario;

    // Public constants so test classes can reference scenarios without magic strings.
    // Using constants (instead of enums) keeps the signature compatible with
    // Test.setMock's loose typing and makes diffs readable.
    public static final String SCENARIO_SUCCESS = 'success';
    public static final String SCENARIO_EMPTY = 'empty';
    public static final String SCENARIO_ERROR = 'error';

    /**
     * @param scenario One of SCENARIO_SUCCESS / SCENARIO_EMPTY / SCENARIO_ERROR.
     *                 An unrecognised scenario yields a blank 0-status response —
     *                 intentional, so a typo in a test fails loudly.
     */
    public NationalizeCalloutMock(String scenario) {
        this.scenario = scenario;
    }

    /**
     * Called by the Apex test framework in place of the real HTTP layer whenever
     * the system under test issues a callout.
     */
    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        // Real Nationalize.io sends JSON; mirror the header so anything that inspects
        // Content-Type (e.g. a future parser change) behaves the same as in prod.
        res.setHeader('Content-Type', 'application/json');

        if (scenario == SCENARIO_SUCCESS) {
            // Happy path: API returns two country predictions. "TR" has the higher
            // probability (0.85), so parseCountry() should pick TR. We include a
            // second entry to also prove the "pick max" logic, not just "pick first".
            res.setStatusCode(200);
            res.setBody('{"count":1,"name":"ali","country":[{"country_id":"TR","probability":0.85},{"country_id":"AZ","probability":0.10}]}');
        } else if (scenario == SCENARIO_EMPTY) {
            // Soft miss: the API answered successfully but could not predict a country
            // for this name. The service should treat this as "no data" and leave the
            // field null.
            res.setStatusCode(200);
            res.setBody('{"count":0,"name":"xyznotaname","country":[]}');
        } else if (scenario == SCENARIO_ERROR) {
            // Hard failure: server-side error. Service should log and skip the record
            // rather than bubbling an exception up.
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
        }

        return res;
    }
}
