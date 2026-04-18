public with sharing class ResellerReconciliationService {
    
    public class ReconcileInput {
        
        @InvocableVariable(required=true)
        public Id resellerId;
        
    }
    
    @InvocableMethod(label='Reconcile Unmatched Opportunities')
    public static void reconcile(List<ReconcileInput> inputs) {
        
        // ----------------------------
        // INPUT VALIDATION
        // ----------------------------
        if (inputs == null || inputs.isEmpty() || inputs[0].resellerId == null) {
            System.debug('No input or resellerId is null');
            return;
        }
        
        Id resellerId = inputs[0].resellerId;
        
        // ----------------------------
        // SAFE RESELLER QUERY (NO EXCEPTION)
        // ----------------------------
        List<Reseller__c> resellerList = [
            SELECT Id, Company_Email__c
            FROM Reseller__c
            WHERE Id = :resellerId
            LIMIT 1
        ];
        
        if (resellerList.isEmpty()) {
            System.debug('No reseller found for Id: ' + resellerId);
            return;
        }
        
        Reseller__c reseller = resellerList[0];
        
        if (String.isBlank(reseller.Company_Email__c)) {
            System.debug('Reseller email is blank');
            return;
        }
        
        // ----------------------------
        // DOMAIN EXTRACTION
        // ----------------------------
        String domain = reseller.Company_Email__c
            .substringAfter('@')
            .toLowerCase()
            .trim();
        
        System.debug('DOMAIN: ' + domain);
        
        // ----------------------------
        // FIND LOGS
        // ----------------------------
        List<Reseller_Match_Log__c> logs = [
            SELECT Id, Opportunity__c, Incoming_Email__c
            FROM Reseller_Match_Log__c
            WHERE Incoming_Email__c != null
            AND Incoming_Email__c LIKE :('%@' + domain)
        ];
        
        System.debug('LOG COUNT: ' + logs.size());
        
        if (logs.isEmpty()) {
            return;
        }
        
        // ----------------------------
        // COLLECT OPPORTUNITY IDS
        // ----------------------------
        Set<Id> oppIds = new Set<Id>();
        
        for (Reseller_Match_Log__c log : logs) {
            if (log.Opportunity__c != null) {
                oppIds.add(log.Opportunity__c);
            }
        }
        
        if (oppIds.isEmpty()) {
            System.debug('No related opportunities found');
            return;
        }
        
        // ----------------------------
        // FETCH OPPORTUNITIES
        // ----------------------------
        List<Opportunity> opportunities = [
            SELECT Id, Reseller__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];
        
        if (opportunities.isEmpty()) {
            System.debug('No opportunities found for logs');
            return;
        }
        
        // ----------------------------
        // UPDATE OPPORTUNITIES
        // ----------------------------
        for (Opportunity opp : opportunities) {
            opp.Reseller__c = reseller.Id;
        }
        
        update opportunities;
        
        System.debug('Opportunities updated: ' + opportunities.size());
        
        // ----------------------------
        // DELETE LOGS
        // ----------------------------
        delete logs;
        
        System.debug('Logs deleted: ' + logs.size());
    }
}