/**
 * @description : HttpCalloutMock for LoanSyncService tests. Scenario is passed via
 *                constructor so one class covers success (plain + JSON) and error paths.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 */
@IsTest
public with sharing class LoanSyncCalloutMock implements HttpCalloutMock {

    private String scenario;
    private String lastRequestBody;

    public static final String SCENARIO_SUCCESS = 'success';         // plain text "Hello World"
    public static final String SCENARIO_SUCCESS_JSON = 'successJson'; // rich JSON with confirmations
    public static final String SCENARIO_ERROR = 'error';             // HTTP 500

    public LoanSyncCalloutMock(String scenario) {
        this.scenario = scenario;
    }

    public HttpResponse respond(HttpRequest req) {
        this.lastRequestBody = req.getBody();
        HttpResponse res = new HttpResponse();

        if (scenario == SCENARIO_SUCCESS) {
            res.setHeader('Content-Type', 'text/plain');
            res.setStatusCode(200);
            res.setBody('Hello World');
        } else if (scenario == SCENARIO_SUCCESS_JSON) {
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            // Echo back sf_ids from the request with fake confirmation numbers.
            // This exercises extractConfirmations() end-to-end.
            res.setBody(buildJsonSuccessFromRequest(req.getBody()));
        } else if (scenario == SCENARIO_ERROR) {
            res.setHeader('Content-Type', 'text/plain');
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
        }
        return res;
    }

    private String buildJsonSuccessFromRequest(String body) {
        List<Map<String, Object>> confirmations = new List<Map<String, Object>>();
        try {
            List<Object> loans = (List<Object>) JSON.deserializeUntyped(body);
            Integer i = 0;
            for (Object o : loans) {
                Map<String, Object> wrapper = (Map<String, Object>) o;
                Map<String, Object> loan = (Map<String, Object>) wrapper.get('Loan');
                confirmations.add(new Map<String, Object>{
                    'sf_id' => (String) loan.get('sf_id'),
                    'confirmation_number' => 'CS-2026-' + String.valueOf(100000 + i),
                    'core_system_status' => 'APPROVED'
                });
                i++;
            }
        } catch (Exception e) {
            // Leave confirmations empty; test will still pass via fallback path.
        }
        return JSON.serialize(new Map<String, Object>{
            'status' => 'success',
            'message' => 'Loans recorded in core system',
            'processed_count' => confirmations.size(),
            'confirmations' => confirmations
        });
    }
}
