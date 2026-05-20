/**
 * @description : Server layer for the File Hub LWC. Wraps Salesforce's ContentDocument
 *                storage with send/receive semantics, categorization, and record linkage.
 *                Used by:
 *                  - Homepage `fileHub` LWC (no recordId)
 *                  - Record-page `fileHub` LWC on Reseller__c / Loan__c
 * @author      : Mustafa Aksu
 * @date        : 2026-05-13
 * @group       : File Hub
 *
 * Design notes:
 * - File_Hub_Entry__c is the metadata wrapper; the actual file bytes live in ContentVersion.
 * - Send flow creates two ContentDocumentLinks: one to the File_Hub_Entry record (so the
 *   file appears in the entry's Files related list) and one to the recipient User (so
 *   they can view/download).
 * - All methods are @AuraEnabled — cacheable=true for read paths (so LWC framework can
 *   cache + refresh via refreshApex), cacheable=false for writes.
 */
public with sharing class FileHubController {

    // ─── Read paths ─────────────────────────────────────────────────

    /**
     * @description Returns entries the current user *owns* and that are not sent to anyone
     *              (Recipient__c is null). Used by the "My Files" tab.
     */
    @AuraEnabled(cacheable=true)
    public static List<EntryDTO> getMyFiles(String category, String searchTerm) {
        Id me = UserInfo.getUserId();
        String searchPattern = '%' + (searchTerm == null ? '' : String.escapeSingleQuotes(searchTerm)) + '%';

        String soql = 'SELECT Id, Name, Sender__c, Sender__r.Name, Recipient__c, Recipient__r.Name, '
            + 'Category__c, Message__c, Read__c, ContentDocument_Id__c, '
            + 'File_Name__c, File_Extension__c, Sent_Date__c, CreatedDate, '
            + 'Related_Reseller__c, Related_Reseller__r.Name, Related_Loan__c, Related_Loan__r.Name '
            + 'FROM File_Hub_Entry__c '
            + 'WHERE Sender__c = :me AND Recipient__c = null';
        if (String.isNotBlank(category) && category != 'All') {
            soql += ' AND Category__c = :category';
        }
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND File_Name__c LIKE :searchPattern';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 200';

        return toDTOs(Database.query(soql, AccessLevel.USER_MODE));
    }

    /**
     * @description Entries the current user *received* — Recipient__c = me.
     *              Drives the Inbox tab + unread badge.
     */
    @AuraEnabled(cacheable=true)
    public static List<EntryDTO> getInbox(String category, String searchTerm) {
        Id me = UserInfo.getUserId();
        String searchPattern = '%' + (searchTerm == null ? '' : String.escapeSingleQuotes(searchTerm)) + '%';

        String soql = 'SELECT Id, Name, Sender__c, Sender__r.Name, Recipient__c, Recipient__r.Name, '
            + 'Category__c, Message__c, Read__c, ContentDocument_Id__c, '
            + 'File_Name__c, File_Extension__c, Sent_Date__c, CreatedDate, '
            + 'Related_Reseller__c, Related_Reseller__r.Name, Related_Loan__c, Related_Loan__r.Name '
            + 'FROM File_Hub_Entry__c '
            + 'WHERE Recipient__c = :me';
        if (String.isNotBlank(category) && category != 'All') {
            soql += ' AND Category__c = :category';
        }
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND File_Name__c LIKE :searchPattern';
        }
        soql += ' ORDER BY Sent_Date__c DESC NULLS LAST, CreatedDate DESC LIMIT 200';

        return toDTOs(Database.query(soql, AccessLevel.USER_MODE));
    }

    /**
     * @description Entries the current user sent to someone else. Drives the Sent tab.
     */
    @AuraEnabled(cacheable=true)
    public static List<EntryDTO> getSent(String category, String searchTerm) {
        Id me = UserInfo.getUserId();
        String searchPattern = '%' + (searchTerm == null ? '' : String.escapeSingleQuotes(searchTerm)) + '%';

        String soql = 'SELECT Id, Name, Sender__c, Sender__r.Name, Recipient__c, Recipient__r.Name, '
            + 'Category__c, Message__c, Read__c, ContentDocument_Id__c, '
            + 'File_Name__c, File_Extension__c, Sent_Date__c, CreatedDate, '
            + 'Related_Reseller__c, Related_Reseller__r.Name, Related_Loan__c, Related_Loan__r.Name '
            + 'FROM File_Hub_Entry__c '
            + 'WHERE Sender__c = :me AND Recipient__c != null';
        if (String.isNotBlank(category) && category != 'All') {
            soql += ' AND Category__c = :category';
        }
        if (String.isNotBlank(searchTerm)) {
            soql += ' AND File_Name__c LIKE :searchPattern';
        }
        soql += ' ORDER BY Sent_Date__c DESC NULLS LAST, CreatedDate DESC LIMIT 200';

        return toDTOs(Database.query(soql, AccessLevel.USER_MODE));
    }

    /**
     * @description Entries linked to a specific record (Reseller__c or Loan__c).
     *              Used by the record-page embed.
     */
    @AuraEnabled(cacheable=true)
    public static List<EntryDTO> getFilesForRecord(Id recordId) {
        if (recordId == null) {
            return new List<EntryDTO>();
        }
        // Determine which lookup to filter on based on the record's sObjectType.
        // Falls through cleanly when recordId points to an unsupported object.
        String sobj = recordId.getSObjectType().getDescribe().getName();
        String filter;
        if (sobj == 'Reseller__c') {
            filter = 'Related_Reseller__c = :recordId';
        } else if (sobj == 'Loan__c') {
            filter = 'Related_Loan__c = :recordId';
        } else {
            return new List<EntryDTO>();
        }

        String soql = 'SELECT Id, Name, Sender__c, Sender__r.Name, Recipient__c, Recipient__r.Name, '
            + 'Category__c, Message__c, Read__c, ContentDocument_Id__c, '
            + 'File_Name__c, File_Extension__c, Sent_Date__c, CreatedDate, '
            + 'Related_Reseller__c, Related_Reseller__r.Name, Related_Loan__c, Related_Loan__r.Name '
            + 'FROM File_Hub_Entry__c '
            + 'WHERE ' + filter
            + ' ORDER BY CreatedDate DESC LIMIT 200';
        return toDTOs(Database.query(soql, AccessLevel.USER_MODE));
    }

    /**
     * @description Inbox unread count for the badge. Single COUNT() query, cheap to poll.
     */
    @AuraEnabled(cacheable=true)
    public static Integer getUnreadCount() {
        Id me = UserInfo.getUserId();
        return [SELECT COUNT() FROM File_Hub_Entry__c WHERE Recipient__c = :me AND Read__c = false WITH USER_MODE];
    }

    /**
     * @description Returns per-category counts for the current view + a special 'All' total.
     *              Drives the category tile bar at the top of the LWC. Cached because the
     *              LWC framework invalidates via refreshApex after writes.
     *
     * @param viewType One of: 'myFiles' | 'inbox' | 'sent' | 'record'
     * @param recordId Only used when viewType = 'record'
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Integer> getCategoryCounts(String viewType, Id recordId) {
        Id me = UserInfo.getUserId();
        String whereClause;

        if (viewType == 'inbox') {
            whereClause = 'Recipient__c = :me';
        } else if (viewType == 'sent') {
            whereClause = 'Sender__c = :me AND Recipient__c != null';
        } else if (viewType == 'record' && recordId != null) {
            String sobj = recordId.getSObjectType().getDescribe().getName();
            if (sobj == 'Reseller__c') {
                whereClause = 'Related_Reseller__c = :recordId';
            } else if (sobj == 'Loan__c') {
                whereClause = 'Related_Loan__c = :recordId';
            } else {
                return buildEmptyCategoryMap();
            }
        } else {
            // Default: myFiles
            whereClause = 'Sender__c = :me AND Recipient__c = null';
        }

        // Initialize all categories to 0 so the UI always has every tile, even empty ones
        Map<String, Integer> result = buildEmptyCategoryMap();

        String soql = 'SELECT Category__c, COUNT(Id) cnt FROM File_Hub_Entry__c '
            + 'WHERE ' + whereClause + ' GROUP BY Category__c';

        Integer total = 0;
        for (AggregateResult ar : Database.query(soql, AccessLevel.USER_MODE)) {
            String cat = (String) ar.get('Category__c');
            Integer cnt = (Integer) ar.get('cnt');
            if (cat != null && result.containsKey(cat)) {
                result.put(cat, cnt);
            }
            total += cnt;
        }
        result.put('All', total);
        return result;
    }

    private static Map<String, Integer> buildEmptyCategoryMap() {
        return new Map<String, Integer>{
            'All' => 0,
            'Contract' => 0,
            'Catalog' => 0,
            'Compliance' => 0,
            'Marketing' => 0,
            'Personal' => 0,
            'Other' => 0
        };
    }

    /**
     * @description Returns a current-month activity matrix — GitHub-style calendar view
     *              for the heatmap. Each day belongs to the running month (1st → last),
     *              with past days coloured by activity, today flagged with isToday,
     *              and future days flagged with isFuture (so the LWC can dim them).
     *
     *              The wrapper DTO also carries the month name so the header can read
     *              "MAY ACTIVITY" instead of "30-DAY ACTIVITY" without an extra round trip.
     */
    @AuraEnabled(cacheable=true)
    public static MonthActivityDTO getMonthActivity() {
        Id me = UserInfo.getUserId();
        Date today = Date.today();
        Date firstOfMonth = Date.newInstance(today.year(), today.month(), 1);
        Integer daysInMonth = Date.daysInMonth(today.year(), today.month());

        DateTime sinceDT = DateTime.newInstance(firstOfMonth, Time.newInstance(0, 0, 0, 0));

        // Aggregate by calendar date — DAY_ONLY() groups by the date portion of CreatedDate
        Map<Date, Integer> countByDate = new Map<Date, Integer>();
        for (AggregateResult ar : [
            SELECT DAY_ONLY(CreatedDate) day, COUNT(Id) cnt
            FROM File_Hub_Entry__c
            WHERE (Sender__c = :me OR Recipient__c = :me)
              AND CreatedDate >= :sinceDT
            WITH USER_MODE
            GROUP BY DAY_ONLY(CreatedDate)
        ]) {
            countByDate.put((Date) ar.get('day'), (Integer) ar.get('cnt'));
        }

        // Build one row per calendar day in the current month, flagging today + future
        // so the LWC can highlight today and dim days that haven't happened yet.
        List<HeatmapDayDTO> days = new List<HeatmapDayDTO>();
        for (Integer i = 0; i < daysInMonth; i++) {
            Date d = firstOfMonth.addDays(i);
            Integer cnt = countByDate.containsKey(d) ? countByDate.get(d) : 0;
            HeatmapDayDTO dto = new HeatmapDayDTO();
            dto.dayDate = d;
            dto.count = cnt;
            dto.level = bucketize(cnt);
            dto.isToday = (d == today);
            dto.isFuture = (d > today);
            days.add(dto);
        }

        // Format the month name once on the server so the LWC doesn't have to deal
        // with locale-aware date formatting in pure JS.
        String monthLabel = DateTime.newInstance(firstOfMonth, Time.newInstance(0, 0, 0, 0))
            .format('MMMM').toUpperCase();

        MonthActivityDTO out = new MonthActivityDTO();
        out.monthName = monthLabel;
        out.daysInMonth = daysInMonth;
        out.todayDayOfMonth = today.day();
        out.days = days;
        return out;
    }

    /**
     * @description Maps a raw count to a discrete 0-4 intensity level so the LWC can
     *              render 5 distinct color shades (light → dark).
     */
    private static Integer bucketize(Integer cnt) {
        if (cnt <= 0) return 0;
        if (cnt <= 1) return 1;
        if (cnt <= 3) return 2;
        if (cnt <= 7) return 3;
        return 4;
    }

    /**
     * @description Returns the last 10 File Hub events involving the current user
     *              (sent or received) within the past 7 days. Drives the Recent Activity
     *              panel at the bottom of the LWC.
     */
    @AuraEnabled(cacheable=true)
    public static List<ActivityDTO> getRecentActivity() {
        Id me = UserInfo.getUserId();
        DateTime since = DateTime.now().addDays(-7);

        List<ActivityDTO> out = new List<ActivityDTO>();
        for (File_Hub_Entry__c e : [
            SELECT Id, Sender__c, Sender__r.Name, Recipient__c, Recipient__r.Name,
                   Category__c, File_Name__c, File_Extension__c, Sent_Date__c, CreatedDate,
                   Related_Reseller__r.Name, Related_Loan__r.Name
            FROM File_Hub_Entry__c
            WHERE (Sender__c = :me OR Recipient__c = :me)
              AND CreatedDate >= :since
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10
        ]) {
            ActivityDTO dto = new ActivityDTO();
            dto.entryId = e.Id;
            dto.fileName = e.File_Name__c;
            dto.category = e.Category__c;
            dto.timestamp = e.Sent_Date__c != null ? e.Sent_Date__c : e.CreatedDate;

            // Determine the action verb + other-party name from the current user's POV
            if (e.Sender__c == me && e.Recipient__c != null) {
                dto.action = 'Sent';
                dto.otherPartyName = (e.Recipient__r == null ? '' : e.Recipient__r.Name);
                dto.iconName = 'utility:share';
            } else if (e.Recipient__c == me) {
                dto.action = 'Received';
                dto.otherPartyName = (e.Sender__r == null ? '' : e.Sender__r.Name);
                dto.iconName = 'utility:inbox';
            } else {
                // Sender == me, no recipient = personal upload
                dto.action = 'Uploaded';
                dto.otherPartyName = '';
                dto.iconName = 'utility:upload';
            }

            // Surface record context if present
            if (e.Related_Reseller__r != null) {
                dto.recordContext = 'on ' + e.Related_Reseller__r.Name;
            } else if (e.Related_Loan__r != null) {
                dto.recordContext = 'on ' + e.Related_Loan__r.Name;
            } else {
                dto.recordContext = '';
            }

            out.add(dto);
        }
        return out;
    }

    /**
     * @description User search for the recipient picker. Filters out inactive users and
     *              the running user. When searchTerm is blank, returns the top 10 active
     *              users alphabetically — drives the "click → see options" UX without
     *              requiring the user to type first.
     */
    @AuraEnabled(cacheable=true)
    public static List<UserDTO> searchUsers(String searchTerm) {
        Id me = UserInfo.getUserId();
        List<UserDTO> out = new List<UserDTO>();

        // Build the query dynamically so blank-term and matching-term paths share one
        // ORDER BY + LIMIT and don't drift apart in behaviour.
        String soql = 'SELECT Id, Name, Email, SmallPhotoUrl, Title FROM User '
            + 'WHERE IsActive = true AND Id != :me';
        if (String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            soql += ' AND (Name LIKE :searchPattern OR Email LIKE :searchPattern)';
        }
        soql += ' ORDER BY Name LIMIT 10';

        for (User u : Database.query(soql, AccessLevel.USER_MODE)) {
            UserDTO dto = new UserDTO();
            dto.userId = u.Id;
            dto.name = u.Name;
            dto.email = u.Email;
            dto.title = u.Title;
            dto.photoUrl = u.SmallPhotoUrl;
            out.add(dto);
        }
        return out;
    }

    /**
     * @description Reseller__c search for the record picker. Blank term returns the top
     *              10 by Name — matches the user-lookup UX so both pickers feel the same.
     */
    @AuraEnabled(cacheable=true)
    public static List<RecordOptionDTO> searchResellers(String searchTerm) {
        List<RecordOptionDTO> out = new List<RecordOptionDTO>();
        String soql = 'SELECT Id, Name, Company_Email__c FROM Reseller__c';
        if (String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            soql += ' WHERE Name LIKE :searchPattern OR Company_Email__c LIKE :searchPattern';
        }
        soql += ' ORDER BY Name LIMIT 10';

        for (Reseller__c r : Database.query(soql, AccessLevel.USER_MODE)) {
            RecordOptionDTO dto = new RecordOptionDTO();
            dto.recordId = r.Id;
            dto.primaryLabel = r.Name;
            dto.secondaryLabel = r.Company_Email__c;
            out.add(dto);
        }
        return out;
    }

    /**
     * @description Loan__c search. Loans have no human-friendly secondary label so we
     *              ORDER BY CreatedDate DESC — the newest 10 loans are usually what the
     *              sender is looking for.
     */
    @AuraEnabled(cacheable=true)
    public static List<RecordOptionDTO> searchLoans(String searchTerm) {
        List<RecordOptionDTO> out = new List<RecordOptionDTO>();
        String soql = 'SELECT Id, Name FROM Loan__c';
        if (String.isNotBlank(searchTerm)) {
            String searchPattern = '%' + String.escapeSingleQuotes(searchTerm) + '%';
            soql += ' WHERE Name LIKE :searchPattern';
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT 10';

        for (Loan__c l : Database.query(soql, AccessLevel.USER_MODE)) {
            RecordOptionDTO dto = new RecordOptionDTO();
            dto.recordId = l.Id;
            dto.primaryLabel = l.Name;
            dto.secondaryLabel = '';
            out.add(dto);
        }
        return out;
    }

    // ─── Write paths ────────────────────────────────────────────────

    /**
     * @description Creates a File_Hub_Entry__c for a freshly uploaded file. If recipientId
     *              is provided, also shares the file with that user.
     *
     * @param contentDocumentId  The Id of the ContentDocument that was just uploaded.
     * @param recipientId        Optional User Id to send the file to.
     * @param category           Category picklist value.
     * @param message            Optional note from sender to recipient.
     * @param relatedResellerId  Optional Reseller__c link.
     * @param relatedLoanId      Optional Loan__c link.
     */
    @AuraEnabled
    public static Id createEntry(
        Id contentDocumentId,
        Id recipientId,
        String category,
        String message,
        Id relatedResellerId,
        Id relatedLoanId
    ) {
        if (contentDocumentId == null) {
            throw new AuraHandledException('A file must be uploaded before sending.');
        }
        if (String.isBlank(category)) {
            throw new AuraHandledException('Category is required.');
        }

        // Look up the ContentDocument to denormalize Title + FileExtension onto the entry.
        // This avoids per-row SOQL joins when the LWC renders the list.
        ContentDocument cd = [
            SELECT Id, Title, FileExtension
            FROM ContentDocument
            WHERE Id = :contentDocumentId
            WITH USER_MODE
            LIMIT 1
        ];

        File_Hub_Entry__c entry = new File_Hub_Entry__c(
            Sender__c = UserInfo.getUserId(),
            Recipient__c = recipientId,
            Category__c = category,
            Message__c = message,
            ContentDocument_Id__c = contentDocumentId,
            File_Name__c = cd.Title,
            File_Extension__c = (cd.FileExtension == null ? null : cd.FileExtension.toLowerCase()),
            Sent_Date__c = (recipientId == null ? null : System.now()),
            Related_Reseller__c = relatedResellerId,
            Related_Loan__c = relatedLoanId
        );
        // Enforce object/field create permissions for the running user (FLS/CRUD).
        insert as user entry;

        // Attach the ContentDocument to the entry record so the standard "Files" related
        // list shows it. Without this link, the file lives only on the uploader's user record.
        insert new ContentDocumentLink(
            ContentDocumentId = contentDocumentId,
            LinkedEntityId = entry.Id,
            ShareType = 'V',  // View
            Visibility = 'AllUsers'
        );

        // If there's a recipient, share BOTH the document AND the wrapper entry with them.
        // - ContentDocumentLink gives them access to the underlying file bytes.
        // - File_Hub_Entry__Share gives them read access to the metadata wrapper so the
        //   Inbox SOQL query returns rows. Without the share, the default OwnerId-based
        //   sharing would hide the entry from the recipient.
        if (recipientId != null) {
            shareWithUser(contentDocumentId, recipientId);
            shareEntryWithUser(entry.Id, recipientId);
        }

        return entry.Id;
    }

    /**
     * @description Marks an Inbox entry as read. Called when the user opens / previews
     *              an entry for the first time. Delegates to FileHubSharingHelper because
     *              the recipient only has Read sharing on the entry — the DML needs to
     *              run in a without-sharing context, with a re-checked auth guard.
     */
    @AuraEnabled
    public static void markAsRead(Id entryId) {
        FileHubSharingHelper.markAsReadInternal(entryId);
    }

    /**
     * @description Deletes an entry. Only the sender can delete; the file itself
     *              (ContentDocument) is preserved if it's linked elsewhere.
     */
    @AuraEnabled
    public static void deleteEntry(Id entryId) {
        if (entryId == null) return;
        File_Hub_Entry__c entry = [
            SELECT Id, Sender__c, ContentDocument_Id__c
            FROM File_Hub_Entry__c
            WHERE Id = :entryId
            WITH USER_MODE
            LIMIT 1
        ];
        if (entry.Sender__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the sender can delete this entry.');
        }
        // Remove the link from the entry to the document. Other links (recipient,
        // related records) survive — the document itself is not deleted, only this entry.
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :entry.Id AND ContentDocumentId = :entry.ContentDocument_Id__c
        ];
        if (!links.isEmpty()) delete links;
        delete entry;
    }

    // ─── Helpers ────────────────────────────────────────────────────

    /**
     * @description Creates a ContentDocumentLink between a document and a user, idempotently.
     *              The unique constraint on (ContentDocumentId, LinkedEntityId) means re-
     *              inserting throws DUPLICATE_VALUE — catch that and treat as success.
     */
    private static void shareWithUser(Id contentDocumentId, Id userId) {
        try {
            insert new ContentDocumentLink(
                ContentDocumentId = contentDocumentId,
                LinkedEntityId = userId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            );
        } catch (DmlException e) {
            // DUPLICATE_VALUE = link already exists, which is fine (idempotent share).
            // Any other DML failure (FLS, sharing rule, etc.) should bubble.
            if (!e.getMessage().contains('DUPLICATE_VALUE')) {
                throw e;
            }
        }
    }

    /**
     * @description Apex-managed sharing for the wrapper entry. Without this, the
     *              recipient's Inbox SOQL returns no rows because the default sharing
     *              model (Private + ReadWrite) only grants access to the owner (sender).
     *
     *              RowCause = Manual means the share is preserved on owner change but
     *              not on record sharing recalculation. For more durable sharing, declare
     *              a custom Apex sharing reason on File_Hub_Entry__c.
     */
    private static void shareEntryWithUser(Id entryId, Id userId) {
        try {
            insert new File_Hub_Entry__Share(
                ParentId = entryId,
                UserOrGroupId = userId,
                AccessLevel = 'Read',
                RowCause = Schema.File_Hub_Entry__Share.RowCause.Manual
            );
        } catch (DmlException e) {
            // Same idempotency story as shareWithUser — silently ignore duplicate shares.
            if (!e.getMessage().contains('DUPLICATE_VALUE')) {
                throw e;
            }
        }
    }

    /**
     * @description Maps File_Hub_Entry__c sObjects to DTOs the LWC can consume without
     *              having to know Salesforce relationship-traversal syntax.
     */
    private static List<EntryDTO> toDTOs(List<File_Hub_Entry__c> entries) {
        List<EntryDTO> out = new List<EntryDTO>();
        for (File_Hub_Entry__c e : entries) {
            EntryDTO dto = new EntryDTO();
            dto.entryId = e.Id;
            dto.entryName = e.Name;
            dto.senderId = e.Sender__c;
            dto.senderName = e.Sender__r == null ? '' : e.Sender__r.Name;
            dto.recipientId = e.Recipient__c;
            dto.recipientName = e.Recipient__r == null ? '' : e.Recipient__r.Name;
            dto.category = e.Category__c;
            dto.message = e.Message__c;
            dto.isRead = e.Read__c;
            dto.contentDocumentId = e.ContentDocument_Id__c;
            dto.fileName = e.File_Name__c;
            dto.fileExtension = e.File_Extension__c;
            dto.sentDate = e.Sent_Date__c;
            dto.createdDate = e.CreatedDate;
            dto.relatedResellerId = e.Related_Reseller__c;
            dto.relatedResellerName = e.Related_Reseller__r == null ? '' : e.Related_Reseller__r.Name;
            dto.relatedLoanId = e.Related_Loan__c;
            dto.relatedLoanName = e.Related_Loan__r == null ? '' : e.Related_Loan__r.Name;
            out.add(dto);
        }
        return out;
    }

    // ─── DTOs ───────────────────────────────────────────────────────

    public class EntryDTO {
        @AuraEnabled public Id entryId;
        @AuraEnabled public String entryName;
        @AuraEnabled public Id senderId;
        @AuraEnabled public String senderName;
        @AuraEnabled public Id recipientId;
        @AuraEnabled public String recipientName;
        @AuraEnabled public String category;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean isRead;
        @AuraEnabled public String contentDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileExtension;
        @AuraEnabled public DateTime sentDate;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public Id relatedResellerId;
        @AuraEnabled public String relatedResellerName;
        @AuraEnabled public Id relatedLoanId;
        @AuraEnabled public String relatedLoanName;
    }

    public class UserDTO {
        @AuraEnabled public Id userId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String title;
        @AuraEnabled public String photoUrl;
    }

    public class ActivityDTO {
        @AuraEnabled public Id entryId;
        @AuraEnabled public String action;          // Sent / Received / Uploaded
        @AuraEnabled public String fileName;
        @AuraEnabled public String category;
        @AuraEnabled public String otherPartyName;  // recipient name if Sent, sender name if Received
        @AuraEnabled public String recordContext;   // 'on Acme Corp' or '' if no related record
        @AuraEnabled public String iconName;        // SLDS icon name
        @AuraEnabled public DateTime timestamp;
    }

    public class HeatmapDayDTO {
        @AuraEnabled public Date dayDate;
        @AuraEnabled public Integer count;
        @AuraEnabled public Integer level;     // 0-4 intensity for color mapping
        @AuraEnabled public Boolean isToday;   // outline this cell in the LWC
        @AuraEnabled public Boolean isFuture;  // render as empty/dimmed (not yet happened)
    }

    public class MonthActivityDTO {
        @AuraEnabled public String monthName;       // e.g. "MAY"
        @AuraEnabled public Integer daysInMonth;    // 28 / 29 / 30 / 31
        @AuraEnabled public Integer todayDayOfMonth;
        @AuraEnabled public List<HeatmapDayDTO> days;
    }

    /**
     * Generic option DTO returned by the Reseller/Loan record pickers. Two-label
     * shape works for any sObject the lookup needs to surface (primary = name,
     * secondary = optional email/identifier).
     */
    public class RecordOptionDTO {
        @AuraEnabled public Id recordId;
        @AuraEnabled public String primaryLabel;
        @AuraEnabled public String secondaryLabel;
    }
}
