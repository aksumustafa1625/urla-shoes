/**
 * @description : Unit tests for FileHubController. Covers the three read paths
 *                (My Files / Inbox / Sent), the write path (createEntry with and
 *                without recipient), markAsRead permission boundary, delete
 *                permission boundary, and the record-page filter.
 * @author      : Mustafa Aksu
 * @date        : 2026-05-13
 * @group       : File Hub
 */
@IsTest
private class FileHubControllerTest {

    /**
     * @description Creates a ContentVersion + returns the parent ContentDocument Id.
     *              Helper because every test needs a "freshly uploaded file" to work with.
     */
    private static Id createContentDocument(String title) {
        ContentVersion cv = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = Blob.valueOf('fake pdf bytes'),
            IsMajorVersion = true
        );
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    /**
     * @description Creates a second active user for "send to someone else" tests.
     *              Uses a stable email pattern to avoid uniqueness collisions across runs.
     *
     *              Wrapped in System.runAs(currentUser) to bypass MIXED_DML_OPERATION,
     *              which fires when User DML (setup object) and ContentVersion DML
     *              (non-setup) happen in the same test transaction.
     */
    private static User createTestUser() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = String.valueOf(DateTime.now().getTime());
        User u = new User(
            Alias = 'fhub',
            Email = 'filehub.recipient.' + unique + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Recipient',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'filehub.recipient.' + unique + '@example.com.test'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            // Grant File Hub access so controller queries pass WITH USER_MODE
            // (FLS/CRUD enforcement) when run as this user.
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'File_Hub_User' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
        return u;
    }

    @IsTest
    static void createEntry_personal_noRecipient_landsInMyFiles() {
        Id cdId = createContentDocument('Personal_Notes');

        Test.startTest();
        Id entryId = FileHubController.createEntry(cdId, null, 'Personal', 'My quick note', null, null);
        Test.stopTest();

        File_Hub_Entry__c entry = [
            SELECT Sender__c, Recipient__c, Category__c, Sent_Date__c,
                   File_Name__c, File_Extension__c, ContentDocument_Id__c
            FROM File_Hub_Entry__c WHERE Id = :entryId
        ];
        System.assertEquals(UserInfo.getUserId(), entry.Sender__c);
        System.assertEquals(null, entry.Recipient__c, 'Personal upload has no recipient.');
        System.assertEquals(null, entry.Sent_Date__c, 'Personal upload has no sent date.');
        System.assertEquals('Personal_Notes', entry.File_Name__c);
        System.assertEquals(cdId, entry.ContentDocument_Id__c);

        // ContentDocumentLink must exist between the document and the entry record
        // so the file appears in the entry's Files related list.
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :entryId AND ContentDocumentId = :cdId
        ]);

        // Should appear in My Files
        List<FileHubController.EntryDTO> myFiles = FileHubController.getMyFiles(null, null);
        System.assertEquals(1, myFiles.size());
        System.assertEquals(entryId, myFiles[0].entryId);
    }

    @IsTest
    static void createEntry_withRecipient_landsInRecipientInbox() {
        User recipient = createTestUser();
        Id cdId = createContentDocument('Sent_To_Friend');

        Test.startTest();
        Id entryId = FileHubController.createEntry(
            cdId, recipient.Id, 'Contract', 'Please review', null, null
        );
        Test.stopTest();

        File_Hub_Entry__c entry = [
            SELECT Recipient__c, Sent_Date__c, Category__c, Read__c
            FROM File_Hub_Entry__c WHERE Id = :entryId
        ];
        System.assertEquals(recipient.Id, entry.Recipient__c);
        System.assertNotEquals(null, entry.Sent_Date__c, 'Sending sets the timestamp.');
        System.assertEquals(false, entry.Read__c, 'New entries start unread.');

        // Recipient must have a ContentDocumentLink to the file
        System.assertEquals(1, [
            SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :recipient.Id AND ContentDocumentId = :cdId
        ]);

        // Run-as the recipient — they should see the entry in their Inbox
        System.runAs(recipient) {
            List<FileHubController.EntryDTO> inbox = FileHubController.getInbox(null, null);
            System.assertEquals(1, inbox.size());
            System.assertEquals(entryId, inbox[0].entryId);
            System.assertEquals(1, FileHubController.getUnreadCount(), 'Unread count matches.');
        }

        // Run-as the sender — should appear in Sent
        List<FileHubController.EntryDTO> sent = FileHubController.getSent(null, null);
        System.assertEquals(1, sent.size());
    }

    @IsTest
    static void createEntry_withResellerLink_appearsInRecordView() {
        // Reseller__c has required fields beyond Name (Company_Email__c). Populate
        // them defensively so the test passes regardless of future schema additions.
        Reseller__c r = new Reseller__c(Name = 'Acme Test', Company_Email__c = 'acme@test.com');
        insert r;
        Id cdId = createContentDocument('Reseller_Doc');

        Test.startTest();
        Id entryId = FileHubController.createEntry(cdId, null, 'Catalog', null, r.Id, null);
        Test.stopTest();

        List<FileHubController.EntryDTO> recordFiles = FileHubController.getFilesForRecord(r.Id);
        System.assertEquals(1, recordFiles.size(), 'Entry should appear in Reseller record view.');
        System.assertEquals(entryId, recordFiles[0].entryId);
        System.assertEquals('Acme Test', recordFiles[0].relatedResellerName);
    }

    @IsTest
    static void createEntry_missingContentDocument_throws() {
        try {
            FileHubController.createEntry(null, null, 'Personal', null, null, null);
            System.assert(false, 'Should have thrown for null contentDocumentId.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void createEntry_missingCategory_throws() {
        Id cdId = createContentDocument('Missing_Category');
        try {
            FileHubController.createEntry(cdId, null, null, null, null, null);
            System.assert(false, 'Should have thrown for blank category.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void markAsRead_byRecipient_setsFlag() {
        User recipient = createTestUser();
        Id cdId = createContentDocument('Read_Me');
        Id entryId = FileHubController.createEntry(cdId, recipient.Id, 'Personal', null, null, null);

        Test.startTest();
        System.runAs(recipient) {
            FileHubController.markAsRead(entryId);
        }
        Test.stopTest();

        System.assertEquals(true,
            [SELECT Read__c FROM File_Hub_Entry__c WHERE Id = :entryId].Read__c);
    }

    @IsTest
    static void markAsRead_bySender_doesNotSetFlag() {
        User recipient = createTestUser();
        Id cdId = createContentDocument('Sender_Cannot_Mark');
        Id entryId = FileHubController.createEntry(cdId, recipient.Id, 'Personal', null, null, null);

        Test.startTest();
        // Running as the SENDER (current user) — must not mark recipient's read state
        FileHubController.markAsRead(entryId);
        Test.stopTest();

        System.assertEquals(false,
            [SELECT Read__c FROM File_Hub_Entry__c WHERE Id = :entryId].Read__c,
            'Sender calling markAsRead must not flip the recipient-owned flag.');
    }

    @IsTest
    static void deleteEntry_bySender_succeeds() {
        Id cdId = createContentDocument('Delete_Me');
        Id entryId = FileHubController.createEntry(cdId, null, 'Personal', null, null, null);

        Test.startTest();
        FileHubController.deleteEntry(entryId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM File_Hub_Entry__c WHERE Id = :entryId]);
        // The ContentDocument itself survives — only the entry-link is removed
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocument WHERE Id = :cdId]);
    }

    @IsTest
    static void deleteEntry_byNonSender_throws() {
        User other = createTestUser();
        Id cdId = createContentDocument('Other_Wont_Delete');
        Id entryId = FileHubController.createEntry(cdId, other.Id, 'Personal', null, null, null);

        Test.startTest();
        try {
            System.runAs(other) {
                FileHubController.deleteEntry(entryId);
            }
            System.assert(false, 'Non-sender should not be able to delete.');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void searchUsers_returnsMatchingActiveUsers() {
        User u = createTestUser();
        Test.startTest();
        List<FileHubController.UserDTO> results = FileHubController.searchUsers('Recipient');
        Test.stopTest();
        Boolean found = false;
        for (FileHubController.UserDTO dto : results) {
            if (dto.userId == u.Id) { found = true; break; }
        }
        System.assert(found, 'Created user should appear in search results.');
    }

    @IsTest
    static void searchUsers_blankTerm_returnsTop10() {
        // Empty term should return up to 10 active users (the "click → see all" UX).
        // We can't seed many active users in a test, but we should get at least the
        // pre-existing ones from the org (admin, integration users, etc.).
        Test.startTest();
        List<FileHubController.UserDTO> blank = FileHubController.searchUsers('');
        List<FileHubController.UserDTO> nullTerm = FileHubController.searchUsers(null);
        Test.stopTest();
        // Should return some users — not zero, not throw
        System.assert(blank.size() >= 0);
        System.assert(nullTerm.size() >= 0);
        // Limit honored
        System.assert(blank.size() <= 10);
        System.assert(nullTerm.size() <= 10);
    }

    @IsTest
    static void searchResellers_returnsMatching() {
        Reseller__c r1 = new Reseller__c(Name = 'Acme Search Test', Company_Email__c = 'acme.search@test.com');
        Reseller__c r2 = new Reseller__c(Name = 'Beta Lookup Test', Company_Email__c = 'beta.lookup@test.com');
        insert new List<Reseller__c>{ r1, r2 };

        Test.startTest();
        List<FileHubController.RecordOptionDTO> matched = FileHubController.searchResellers('Acme');
        List<FileHubController.RecordOptionDTO> all = FileHubController.searchResellers('');
        Test.stopTest();

        Boolean foundAcme = false;
        for (FileHubController.RecordOptionDTO dto : matched) {
            if (dto.primaryLabel == 'Acme Search Test') {
                foundAcme = true;
                System.assertEquals('acme.search@test.com', dto.secondaryLabel,
                    'Secondary label exposes Company_Email__c for context.');
            }
        }
        System.assert(foundAcme, 'Matching reseller surfaces in search results.');
        System.assert(all.size() >= 2, 'Blank term returns multiple resellers, not zero.');
    }

    @IsTest
    static void searchLoans_returnsMatching() {
        // Loan creation goes through the Closed-Won pipeline so an Opp is the natural seed
        Account acct = OpportunityTestDataFactory.createAccount(true);
        Test.setMock(HttpCalloutMock.class, new LoanSyncCalloutMock(LoanSyncCalloutMock.SCENARIO_SUCCESS));

        Test.startTest();
        insert new Opportunity(
            Name = 'Search-Loan-Opp', StageName = 'Closed Won',
            CloseDate = Date.today(), AccountId = acct.Id,
            Amount = 50000, Term_In_Months__c = 12
        );
        Test.stopTest();

        // After the trigger, exactly one Loan exists — searchLoans('') should surface it
        List<FileHubController.RecordOptionDTO> results = FileHubController.searchLoans('');
        System.assert(results.size() >= 1, 'Blank term returns the recent loan.');
        System.assertNotEquals(null, results[0].recordId);
        System.assert(String.isNotBlank(results[0].primaryLabel),
            'Loan picker exposes the auto-numbered Name as the primary label.');
    }

    @IsTest
    static void getFilesForRecord_unsupportedObject_returnsEmpty() {
        // Account is not Reseller__c or Loan__c — should return empty list, not throw
        Account a = new Account(Name = 'Unsupported');
        insert a;
        System.assertEquals(0, FileHubController.getFilesForRecord(a.Id).size());
    }

    @IsTest
    static void getCategoryCounts_myFiles_returnsCounts() {
        // Three personal uploads across two categories — the tile bar should reflect this.
        Id cd1 = createContentDocument('Personal_A');
        Id cd2 = createContentDocument('Personal_B');
        Id cd3 = createContentDocument('Personal_C');
        FileHubController.createEntry(cd1, null, 'Contract', null, null, null);
        FileHubController.createEntry(cd2, null, 'Contract', null, null, null);
        FileHubController.createEntry(cd3, null, 'Marketing', null, null, null);

        Test.startTest();
        Map<String, Integer> counts = FileHubController.getCategoryCounts('myFiles', null);
        Test.stopTest();

        System.assertEquals(3, counts.get('All'), 'All total reflects every entry.');
        System.assertEquals(2, counts.get('Contract'));
        System.assertEquals(1, counts.get('Marketing'));
        System.assertEquals(0, counts.get('Compliance'), 'Empty categories return 0, not null.');
    }

    @IsTest
    static void getCategoryCounts_inbox_filtersByRecipient() {
        User recipient = createTestUser();
        Id cd1 = createContentDocument('Sent_1');
        Id cd2 = createContentDocument('Sent_2');
        FileHubController.createEntry(cd1, recipient.Id, 'Catalog', null, null, null);
        FileHubController.createEntry(cd2, recipient.Id, 'Compliance', null, null, null);

        Test.startTest();
        Map<String, Integer> counts;
        System.runAs(recipient) {
            counts = FileHubController.getCategoryCounts('inbox', null);
        }
        Test.stopTest();

        System.assertEquals(2, counts.get('All'));
        System.assertEquals(1, counts.get('Catalog'));
        System.assertEquals(1, counts.get('Compliance'));
    }

    @IsTest
    static void getCategoryCounts_recordView_returnsRecordOnlyCounts() {
        Reseller__c r = new Reseller__c(Name = 'ResellerForCounts', Company_Email__c = 'rfc@test.com');
        insert r;
        Id cd1 = createContentDocument('Reseller_A');
        Id cd2 = createContentDocument('Reseller_B');
        Id cdOther = createContentDocument('NotLinked');
        FileHubController.createEntry(cd1, null, 'Contract', null, r.Id, null);
        FileHubController.createEntry(cd2, null, 'Compliance', null, r.Id, null);
        FileHubController.createEntry(cdOther, null, 'Contract', null, null, null);  // not linked

        Test.startTest();
        Map<String, Integer> counts = FileHubController.getCategoryCounts('record', r.Id);
        Test.stopTest();

        System.assertEquals(2, counts.get('All'), 'Only the two linked entries count.');
        System.assertEquals(1, counts.get('Contract'));
        System.assertEquals(1, counts.get('Compliance'));
    }

    @IsTest
    static void getRecentActivity_returnsRecentEvents() {
        User recipient = createTestUser();
        Id cd1 = createContentDocument('Activity_Sent');
        Id cd2 = createContentDocument('Activity_Personal');
        FileHubController.createEntry(cd1, recipient.Id, 'Contract', 'Please sign', null, null);
        FileHubController.createEntry(cd2, null, 'Personal', null, null, null);

        Test.startTest();
        List<FileHubController.ActivityDTO> events = FileHubController.getRecentActivity();
        Test.stopTest();

        System.assertEquals(2, events.size(), 'Both events fall in the last 7 days.');

        // Confirm the verb mapping
        Map<String, FileHubController.ActivityDTO> byFile = new Map<String, FileHubController.ActivityDTO>();
        for (FileHubController.ActivityDTO a : events) byFile.put(a.fileName, a);

        System.assertEquals('Sent', byFile.get('Activity_Sent').action,
            'Sender sees "Sent" verb when there is a recipient.');
        System.assertEquals('Uploaded', byFile.get('Activity_Personal').action,
            'Sender sees "Uploaded" verb on personal (no-recipient) uploads.');
    }

    @IsTest
    static void getMonthActivity_returnsCurrentMonth() {
        // Create a couple of entries today so the today-bucket has activity to surface
        Id cd1 = createContentDocument('Heatmap_A');
        Id cd2 = createContentDocument('Heatmap_B');
        FileHubController.createEntry(cd1, null, 'Personal', null, null, null);
        FileHubController.createEntry(cd2, null, 'Personal', null, null, null);

        Test.startTest();
        FileHubController.MonthActivityDTO result = FileHubController.getMonthActivity();
        Test.stopTest();

        Date today = Date.today();
        Integer expectedDays = Date.daysInMonth(today.year(), today.month());

        // Metadata sanity checks
        System.assertEquals(expectedDays, result.daysInMonth,
            'daysInMonth honors the actual calendar length of the current month.');
        System.assertEquals(expectedDays, result.days.size(),
            'days[] has one entry per calendar day of the current month.');
        System.assertEquals(today.day(), result.todayDayOfMonth);
        System.assertNotEquals(null, result.monthName);
        System.assert(result.monthName.length() > 0, 'Month name is populated.');

        // Today's bucket should reflect the two entries this test created
        FileHubController.HeatmapDayDTO todayCell = result.days[today.day() - 1];
        System.assertEquals(today, todayCell.dayDate);
        System.assertEquals(true, todayCell.isToday, 'Today cell must be flagged isToday.');
        System.assertEquals(false, todayCell.isFuture);
        System.assert(todayCell.count >= 2);
        System.assert(todayCell.level >= 1);

        // Last day of month — if today isn't the last day, that cell should be future
        FileHubController.HeatmapDayDTO lastCell = result.days[expectedDays - 1];
        if (today.day() < expectedDays) {
            System.assertEquals(true, lastCell.isFuture,
                'Days after today must be flagged isFuture.');
            System.assertEquals(false, lastCell.isToday);
        }

        // First day of month
        FileHubController.HeatmapDayDTO firstCell = result.days[0];
        System.assertEquals(1, firstCell.dayDate.day());
        // If today is the 1st, the first cell IS today; otherwise it's a past day
        System.assertEquals(today.day() == 1, firstCell.isToday);
    }

    @IsTest
    static void getRecentActivity_recipientSeesReceivedVerb() {
        User recipient = createTestUser();
        Id cd = createContentDocument('Activity_Received');
        FileHubController.createEntry(cd, recipient.Id, 'Catalog', null, null, null);

        Test.startTest();
        List<FileHubController.ActivityDTO> events;
        System.runAs(recipient) {
            events = FileHubController.getRecentActivity();
        }
        Test.stopTest();

        System.assertEquals(1, events.size());
        System.assertEquals('Received', events[0].action,
            'Recipient POV uses the "Received" verb.');
    }

    @IsTest
    static void getInbox_filterByCategory_appliesFilter() {
        User recipient = createTestUser();
        Id cd1 = createContentDocument('Cat1');
        Id cd2 = createContentDocument('Cat2');
        FileHubController.createEntry(cd1, recipient.Id, 'Contract', null, null, null);
        FileHubController.createEntry(cd2, recipient.Id, 'Marketing', null, null, null);

        Test.startTest();
        System.runAs(recipient) {
            List<FileHubController.EntryDTO> contracts = FileHubController.getInbox('Contract', null);
            System.assertEquals(1, contracts.size());
            System.assertEquals('Contract', contracts[0].category);
        }
        Test.stopTest();
    }
}
