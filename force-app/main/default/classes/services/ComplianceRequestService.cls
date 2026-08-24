/**
 * The autonomous compliance loop's request side.
 *
 *   detect gap (ComplianceService) → raise Document_Request__c → email the
 *   reseller's primary contact → (partner uploads) → AI classifies
 *   (DocumentIntelligenceService) → autoFulfill() closes the matching request.
 *
 * Requests are de-duplicated: a category with an open ('Requested') request is
 * not re-requested. Email is best-effort — a send failure never blocks the request.
 */
public with sharing class ComplianceRequestService {

    public class RequestInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public String label;
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public Datetime requestedDate;
        @AuraEnabled public Datetime fulfilledDate;
    }

    public class SweepResult {
        @AuraEnabled public Integer created;
        @AuraEnabled public Integer skipped;
        @AuraEnabled public Integer emailed;
        @AuraEnabled public String message;
    }

    @AuraEnabled(cacheable=true)
    public static List<RequestInfo> getRequests(Id resellerId) {
        if (resellerId == null) {
            throw new AuraHandledException('A reseller id is required');
        }
        List<RequestInfo> out = new List<RequestInfo>();
        for (Document_Request__c r : [
            SELECT Id, Name, Document_Category__c, Requirement_Label__c, Status__c,
                   Reason__c, Requested_Date__c, Fulfilled_Date__c
            FROM Document_Request__c
            WHERE Reseller__c = :resellerId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ]) {
            RequestInfo info = new RequestInfo();
            info.id = r.Id;
            info.name = r.Name;
            info.category = r.Document_Category__c;
            info.label = r.Requirement_Label__c;
            info.status = r.Status__c;
            info.reason = r.Reason__c;
            info.requestedDate = r.Requested_Date__c;
            info.fulfilledDate = r.Fulfilled_Date__c;
            out.add(info);
        }
        return out;
    }

    /**
     * Scans a reseller's compliance and raises a request for every MISSING or
     * EXPIRED requirement that does not already have an open request.
     */
    @AuraEnabled
    public static SweepResult requestAllGaps(Id resellerId) {
        if (resellerId == null) {
            throw new AuraHandledException('A reseller id is required');
        }
        ComplianceService.ResellerComplianceRow row =
            ComplianceService.getResellerCompliance(resellerId);

        Set<String> alreadyOpen = openRequestCategories(resellerId);

        List<Document_Request__c> toCreate = new List<Document_Request__c>();
        Integer skipped = 0;
        for (ComplianceService.CellStatus cell : row.cells) {
            Boolean isGap = cell.status == 'MISSING' || cell.status == 'EXPIRED';
            if (!isGap) {
                continue;
            }
            if (alreadyOpen.contains(cell.category)) {
                skipped++;
                continue;
            }
            toCreate.add(newRequest(resellerId, cell.category, cell.label, reasonFor(cell)));
        }

        SweepResult result = new SweepResult();
        result.created = toCreate.size();
        result.skipped = skipped;
        result.emailed = 0;

        if (!toCreate.isEmpty()) {
            insert as user toCreate;
            result.emailed = sendRequestEmail(resellerId, toCreate);
        }
        result.message = result.created == 0
            ? (skipped > 0 ? 'All gaps already have open requests.' : 'No gaps — reseller is compliant.')
            : 'Raised ' + result.created + ' request(s)'
                + (result.emailed > 0 ? ' and emailed the primary contact.' : '.');
        return result;
    }

    @AuraEnabled
    public static RequestInfo requestDocument(Id resellerId, String category, String label, String reason) {
        if (resellerId == null || String.isBlank(category)) {
            throw new AuraHandledException('Reseller and category are required');
        }
        if (openRequestCategories(resellerId).contains(category)) {
            throw new AuraHandledException('An open request already exists for this document.');
        }
        Document_Request__c req = newRequest(resellerId, category, label, reason);
        insert as user req;
        sendRequestEmail(resellerId, new List<Document_Request__c>{ req });

        RequestInfo info = new RequestInfo();
        info.id = req.Id;
        info.category = category;
        info.label = label;
        info.status = 'Requested';
        info.reason = reason;
        info.requestedDate = req.Requested_Date__c;
        return info;
    }

    /**
     * Closes any open request for the entry's reseller + category. Called by
     * DocumentIntelligenceService after an AI classification is applied — this is
     * the "validate → act" step that completes the loop. Returns # fulfilled.
     */
    public static Integer autoFulfill(File_Hub_Entry__c entry) {
        if (entry == null || entry.Related_Reseller__c == null || String.isBlank(entry.Category__c)) {
            return 0;
        }
        List<Document_Request__c> open = [
            SELECT Id, Status__c
            FROM Document_Request__c
            WHERE Reseller__c = :entry.Related_Reseller__c
              AND Document_Category__c = :entry.Category__c
              AND Status__c = 'Requested'
            WITH USER_MODE
        ];
        if (open.isEmpty()) {
            return 0;
        }
        for (Document_Request__c r : open) {
            r.Status__c = 'Fulfilled';
            r.Fulfilled_Entry__c = entry.Id;
            r.Fulfilled_Date__c = System.now();
        }
        update as user open;
        return open.size();
    }

    /* ─── INTERNALS ─────────────────────────────────────────────────────── */

    private static Set<String> openRequestCategories(Id resellerId) {
        Set<String> cats = new Set<String>();
        for (Document_Request__c r : [
            SELECT Document_Category__c
            FROM Document_Request__c
            WHERE Reseller__c = :resellerId AND Status__c = 'Requested'
            WITH USER_MODE
        ]) {
            cats.add(r.Document_Category__c);
        }
        return cats;
    }

    private static Document_Request__c newRequest(Id resellerId, String category, String label, String reason) {
        return new Document_Request__c(
            Reseller__c = resellerId,
            Document_Category__c = category,
            Requirement_Label__c = label,
            Status__c = 'Requested',
            Reason__c = reason,
            Requested_Date__c = System.now(),
            Message__c = buildMessage(label, reason)
        );
    }

    private static String reasonFor(ComplianceService.CellStatus cell) {
        if (cell.status == 'EXPIRED') {
            return cell.expiryDate == null ? 'Expired' : 'Expired on ' + cell.expiryDate.format();
        }
        return 'Missing';
    }

    private static String buildMessage(String label, String reason) {
        return 'Dear partner,\n\nTo keep your reseller account compliant, please upload your '
            + label + ' via the partner portal. Reason: ' + reason + '.\n\n'
            + 'Once uploaded it will be validated automatically.\n\nThank you,\nUrla Shoes Partner Compliance';
    }

    /** Best-effort email to the reseller's primary contact. Never throws. */
    private static Integer sendRequestEmail(Id resellerId, List<Document_Request__c> requests) {
        try {
            List<Reseller__c> rs = [
                SELECT Name, Primary_Contact__r.Email, Primary_Contact__r.Name
                FROM Reseller__c
                WHERE Id = :resellerId
                WITH USER_MODE
                LIMIT 1
            ];
            if (rs.isEmpty() || rs[0].Primary_Contact__r == null
                || String.isBlank(rs[0].Primary_Contact__r.Email)) {
                return 0;
            }
            List<String> labels = new List<String>();
            for (Document_Request__c r : requests) {
                labels.add('• ' + r.Requirement_Label__c + ' (' + r.Reason__c + ')');
            }
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ rs[0].Primary_Contact__r.Email });
            mail.setSubject('Action required: compliance documents for ' + rs[0].Name);
            mail.setPlainTextBody(
                'Dear ' + rs[0].Primary_Contact__r.Name + ',\n\n'
                + 'The following compliance document(s) are required for your reseller account:\n\n'
                + String.join(labels, '\n')
                + '\n\nPlease upload them via the partner portal. Uploaded documents are validated automatically.\n\n'
                + 'Thank you,\nUrla Shoes Partner Compliance'
            );
            mail.setSaveAsActivity(false);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            return 1;
        } catch (Exception ex) {
            System.debug('Compliance request email skipped: ' + ex.getMessage());
            return 0;
        }
    }
}
