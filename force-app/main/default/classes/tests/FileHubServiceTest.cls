@isTest
private class FileHubServiceTest {

    @isTest
    static void deletingContentDocumentRemovesOrphanEntry() {
        // Upload a real file → creates a ContentDocument
        ContentVersion cv = new ContentVersion(
            Title = 'Ghost Test',
            PathOnClient = 'ghost.txt',
            VersionData = Blob.valueOf('hello world')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        // Wrapper entry pointing at that document
        File_Hub_Entry__c entry = new File_Hub_Entry__c(
            Sender__c = UserInfo.getUserId(),
            Category__c = 'Other',
            ContentDocument_Id__c = docId,
            File_Name__c = 'Ghost Test.txt'
        );
        insert entry;

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :docId];
        Test.stopTest();

        // The trigger should have removed the now-orphaned wrapper
        System.assertEquals(
            0,
            [SELECT COUNT() FROM File_Hub_Entry__c WHERE Id = :entry.Id],
            'orphaned wrapper should be deleted with its ContentDocument'
        );
    }

    @isTest
    static void unrelatedEntriesSurvive() {
        ContentVersion cv = new ContentVersion(
            Title = 'Keep Me',
            PathOnClient = 'keep.txt',
            VersionData = Blob.valueOf('keep')
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;

        // Entry that points at a DIFFERENT (fake) document id — must not be touched
        File_Hub_Entry__c other = new File_Hub_Entry__c(
            Sender__c = UserInfo.getUserId(),
            Category__c = 'Other',
            ContentDocument_Id__c = 'Demo00000000000077',
            File_Name__c = 'Unrelated.txt'
        );
        insert other;

        Test.startTest();
        delete [SELECT Id FROM ContentDocument WHERE Id = :docId];
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM File_Hub_Entry__c WHERE Id = :other.Id],
            'entries pointing at other documents must survive'
        );
    }

    @isTest
    static void emptyInputIsNoOp() {
        Test.startTest();
        FileHubService.deleteOrphanedEntries(new Set<Id>());
        FileHubService.deleteOrphanedEntries(null);
        Test.stopTest();
        // No exception = pass
        System.assert(true);
    }
}
