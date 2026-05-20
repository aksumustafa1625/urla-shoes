@isTest
private class DocumentIntelligenceServiceTest {

    private static Reseller__c makeReseller() {
        Reseller__c r = new Reseller__c(
            Name = 'AI Test Reseller',
            Company_Email__c = 'aitest@test.com',
            City__c = 'Berlin',
            Country__c = 'Germany'
        );
        insert r;
        return r;
    }

    private static File_Hub_Entry__c makeEntry(Id resellerId, String category) {
        File_Hub_Entry__c e = new File_Hub_Entry__c(
            Sender__c = UserInfo.getUserId(),
            Related_Reseller__c = resellerId,
            Category__c = category,
            File_Name__c = 'Tax Certificate 2026.pdf',
            File_Extension__c = 'pdf',
            Message__c = 'Updated tax certificate for 2026',
            ContentDocument_Id__c = 'Demo00000000000099'
        );
        insert e;
        return e;
    }

    @isTest
    static void classifyAppliesCategoryAndExpiry() {
        Reseller__c r = makeReseller();
        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal');

        DocumentIntelligenceService.mockLlmText =
            '{"category":"Tax Document","confidence":92,"expiryDate":"2027-03-01","summary":"German tax certificate valid through Q1 2027."}';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(true, res.applied, 'should apply');
        System.assertEquals('Tax Document', res.suggestedCategory);
        System.assertEquals(92, res.confidence);
        System.assertEquals(Date.newInstance(2027, 3, 1), res.expiryDate);
        System.assertEquals('Personal', res.previousCategory);

        File_Hub_Entry__c updated = [SELECT Category__c, Expiry_Date__c FROM File_Hub_Entry__c WHERE Id = :e.Id];
        System.assertEquals('Tax Document', updated.Category__c);
        System.assertEquals(Date.newInstance(2027, 3, 1), updated.Expiry_Date__c);
    }

    @isTest
    static void classifyToleratesJsonCodeFences() {
        Reseller__c r = makeReseller();
        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal');

        DocumentIntelligenceService.mockLlmText =
            '```json\n{"category":"Insurance","confidence":80,"expiryDate":null,"summary":"Liability insurance."}\n```';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(true, res.applied);
        System.assertEquals('Insurance', res.suggestedCategory);
        System.assertEquals(null, res.expiryDate, 'null expiry stays null');
    }

    @isTest
    static void unknownCategoryIsNotApplied() {
        Reseller__c r = makeReseller();
        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal');

        DocumentIntelligenceService.mockLlmText =
            '{"category":"Spaceship Manual","confidence":40,"expiryDate":null,"summary":"Unknown."}';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(false, res.applied, 'invalid category not applied');
        File_Hub_Entry__c unchanged = [SELECT Category__c FROM File_Hub_Entry__c WHERE Id = :e.Id];
        System.assertEquals('Personal', unchanged.Category__c, 'category unchanged');
    }

    @isTest
    static void garbageResponseDoesNotApply() {
        Reseller__c r = makeReseller();
        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal');

        DocumentIntelligenceService.mockLlmText = 'this is not json at all';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(false, res.applied);
        System.assertNotEquals(null, res.message);
    }

    @isTest
    static void emptyResponseHandled() {
        Reseller__c r = makeReseller();
        File_Hub_Entry__c e = makeEntry(r.Id, 'Personal');

        DocumentIntelligenceService.mockLlmText = '';

        Test.startTest();
        DocumentIntelligenceService.ClassificationResult res =
            DocumentIntelligenceService.classifyAndApply(e.Id);
        Test.stopTest();

        System.assertEquals(false, res.applied);
    }

    @isTest
    static void getResellerEntriesReturnsFiles() {
        Reseller__c r = makeReseller();
        makeEntry(r.Id, 'Contract');

        Test.startTest();
        List<DocumentIntelligenceService.EntryInfo> entries =
            DocumentIntelligenceService.getResellerEntries(r.Id);
        Test.stopTest();

        System.assertEquals(1, entries.size());
        System.assertEquals('pdf', entries[0].fileExtension);
        System.assertEquals('Contract', entries[0].category);
    }

    @isTest
    static void nullArgumentsThrow() {
        Integer threw = 0;
        try { DocumentIntelligenceService.classifyAndApply(null); } catch (AuraHandledException ex) { threw++; }
        try { DocumentIntelligenceService.getResellerEntries(null); } catch (AuraHandledException ex) { threw++; }
        System.assertEquals(2, threw);
    }

    @isTest
    static void parseDateEdgeCases() {
        System.assertEquals(null, DocumentIntelligenceService.parseDate(null));
        System.assertEquals(null, DocumentIntelligenceService.parseDate('null'));
        System.assertEquals(null, DocumentIntelligenceService.parseDate('not-a-date'));
        System.assertEquals(Date.newInstance(2026, 12, 31), DocumentIntelligenceService.parseDate('2026-12-31'));
        System.assertEquals(Date.newInstance(2026, 1, 5), DocumentIntelligenceService.parseDate('2026-01-05T00:00:00Z'));
    }
}
