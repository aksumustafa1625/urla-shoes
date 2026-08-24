@isTest
private class ComplianceRequestServiceTest {

    private static Reseller__c makeReseller(String name, Boolean withContact) {
        Reseller__c r = new Reseller__c(
            Name = name,
            Company_Email__c = name.deleteWhitespace().toLowerCase() + '@test.com',
            City__c = 'Munich',
            Country__c = 'Germany'
        );
        if (withContact) {
            Contact c = new Contact(
                LastName = 'Partner ' + name,
                Email = 'partner_' + name.deleteWhitespace().toLowerCase() + '@test.com'
            );
            insert c;
            r.Primary_Contact__c = c.Id;
        }
        insert r;
        return r;
    }

    private static File_Hub_Entry__c makeEntry(Id resellerId, String category, Date expiry) {
        File_Hub_Entry__c e = new File_Hub_Entry__c(
            Sender__c = UserInfo.getUserId(),
            Related_Reseller__c = resellerId,
            Category__c = category,
            File_Name__c = category + ' (test)',
            ContentDocument_Id__c = 'Demo' + String.valueOf(Math.abs(Crypto.getRandomLong())).left(14),
            Expiry_Date__c = expiry
        );
        insert e;
        return e;
    }

    @isTest
    static void requestAllGapsCreatesAndDedupes() {
        Reseller__c r = makeReseller('Gap Co', true); // no files → every requirement missing
        Integer reqCount = ComplianceService.getRequirements().size();

        Test.startTest();
        ComplianceRequestService.SweepResult first = ComplianceRequestService.requestAllGaps(r.Id);
        ComplianceRequestService.SweepResult second = ComplianceRequestService.requestAllGaps(r.Id);
        Test.stopTest();

        System.assertEquals(reqCount, first.created, 'one request per missing requirement');
        System.assertEquals(0, second.created, 'second sweep creates nothing');
        System.assertEquals(reqCount, second.skipped, 'all already open → skipped');

        List<Document_Request__c> reqs = [SELECT Id, Status__c FROM Document_Request__c WHERE Reseller__c = :r.Id];
        System.assertEquals(reqCount, reqs.size());
    }

    @isTest
    static void fullyCompliantHasNoGaps() {
        Reseller__c r = makeReseller('Clean Co', false);
        for (ComplianceService.RequirementDef def : ComplianceService.getRequirements()) {
            makeEntry(r.Id, def.category, Date.today().addDays(300));
        }

        Test.startTest();
        ComplianceRequestService.SweepResult res = ComplianceRequestService.requestAllGaps(r.Id);
        Test.stopTest();

        System.assertEquals(0, res.created, 'compliant reseller → no requests');
    }

    @isTest
    static void requestDocumentRejectsDuplicate() {
        Reseller__c r = makeReseller('Dup Co', false);

        Test.startTest();
        ComplianceRequestService.RequestInfo info =
            ComplianceRequestService.requestDocument(r.Id, 'Bank Details', 'Bank Account Details', 'Missing');
        Boolean threw = false;
        try {
            ComplianceRequestService.requestDocument(r.Id, 'Bank Details', 'Bank Account Details', 'Missing');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertNotEquals(null, info.id);
        System.assertEquals('Requested', info.status);
        System.assertEquals(true, threw, 'duplicate open request should be rejected');
    }

    @isTest
    static void autoFulfillClosesMatchingRequest() {
        Reseller__c r = makeReseller('Fulfill Co', false);
        ComplianceRequestService.requestDocument(r.Id, 'Bank Details', 'Bank Account Details', 'Missing');

        File_Hub_Entry__c e = makeEntry(r.Id, 'Bank Details', null);
        File_Hub_Entry__c loaded = [
            SELECT Id, Related_Reseller__c, Category__c FROM File_Hub_Entry__c WHERE Id = :e.Id
        ];

        Test.startTest();
        Integer fulfilled = ComplianceRequestService.autoFulfill(loaded);
        Test.stopTest();

        System.assertEquals(1, fulfilled);
        Document_Request__c req = [
            SELECT Status__c, Fulfilled_Entry__c, Fulfilled_Date__c
            FROM Document_Request__c WHERE Reseller__c = :r.Id LIMIT 1
        ];
        System.assertEquals('Fulfilled', req.Status__c);
        System.assertEquals(e.Id, req.Fulfilled_Entry__c);
        System.assertNotEquals(null, req.Fulfilled_Date__c);
    }

    @isTest
    static void autoFulfillNoMatchIsNoOp() {
        Reseller__c r = makeReseller('NoMatch Co', false);
        File_Hub_Entry__c e = makeEntry(r.Id, 'Catalog', null);
        File_Hub_Entry__c loaded = [
            SELECT Id, Related_Reseller__c, Category__c FROM File_Hub_Entry__c WHERE Id = :e.Id
        ];

        Test.startTest();
        Integer fulfilled = ComplianceRequestService.autoFulfill(loaded);
        Test.stopTest();

        System.assertEquals(0, fulfilled, 'no open request → nothing fulfilled');
    }

    @isTest
    static void endToEndClassifyFulfillsRequest() {
        Reseller__c r = makeReseller('Loop Co', false);
        ComplianceRequestService.requestDocument(r.Id, 'Tax Document', 'Tax Certificate', 'Missing');

        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal', null); // starts unclassified-ish
        DocumentIntelligenceService.mockLlmText =
            '{"category":"Tax Document","confidence":90,"expiryDate":"2027-01-31","summary":"Tax cert."}';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(true, res.applied);
        System.assert(res.message.contains('fulfilled an open request'), 'classify should close the request');
        Document_Request__c req = [SELECT Status__c FROM Document_Request__c WHERE Reseller__c = :r.Id LIMIT 1];
        System.assertEquals('Fulfilled', req.Status__c);
    }

    @isTest
    static void getRequestsAndNullGuards() {
        Reseller__c r = makeReseller('List Co', false);
        ComplianceRequestService.requestDocument(r.Id, 'Insurance', 'Liability Insurance', 'Missing');

        List<ComplianceRequestService.RequestInfo> reqList = ComplianceRequestService.getRequests(r.Id);
        System.assertEquals(1, reqList.size());
        System.assertEquals('Insurance', reqList[0].category);

        Integer threw = 0;
        try { ComplianceRequestService.getRequests(null); } catch (AuraHandledException ex) { threw++; }
        try { ComplianceRequestService.requestAllGaps(null); } catch (AuraHandledException ex) { threw++; }
        try { ComplianceRequestService.requestDocument(null, null, null, null); } catch (AuraHandledException ex) { threw++; }
        System.assertEquals(3, threw);
    }
}
