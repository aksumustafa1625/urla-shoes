/**
 * @description
 * <h2>Reseller Match Log Service</h2>
 *
 * Service class responsible for creating diagnostic log records
 * when an Opportunity cannot be matched to a reseller.
 *
 * This class runs in AFTER trigger context because Opportunity Id
 * must exist before creating log records.
 *
 * <h2>Purpose</h2>
 *
 * Provides visibility into reseller matching failures and allows
 * administrators to review unmatched records for manual correction.
 *
 * <h2>Architecture Role</h2>
 *
 * OpportunityTrigger
 *        ↓
 * OpportunityResellerTriggerHandler
 *        ↓
 * ResellerMatchingEngine
 *        ↓
 * (no match)
 *        ↓
 * ResellerMatchLogService
 *
 * <h2>Log Object</h2>
 *
 * Reseller_Match_Log__c
 *
 * Fields typically stored:
 *  - Opportunity__c
 *  - Incoming_Email__c
 *  - Extracted_Domain__c
 *  - Reason__c
 *  - Created_From_Trigger__c
 *
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class ResellerMatchLogService {
    
    /**
     * @description
     * Creates log records for Opportunities that still do not have
     * a reseller assigned after the matching engine executes.
     *
     * Prevents duplicate logs per Opportunity.
     *
     * @param opportunities Trigger.new list from AFTER trigger context
     */
    public static void createLogsAfter(List<Opportunity> opportunities) {
        
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }
        
        Set<Id> oppIds = new Set<Id>();
        Map<Id, String> emailByOpp = new Map<Id, String>();
        Map<Id, String> domainByOpp = new Map<Id, String>();
        
        /*
        STEP 1
            Identify Opportunities that failed matching
             */
        
        for (Opportunity opp : opportunities) {
            
            if (opp.Reseller__c != null) {
                continue;
            }
            
            String email = EmailUtils.normalizeEmail(opp.Reseller_Email__c);
            
            if (email == null) {
                continue;
            }
            
            oppIds.add(opp.Id);
            emailByOpp.put(opp.Id, email);
            domainByOpp.put(
                opp.Id,
            EmailUtils.extractDomain(email)
                );
        }
        
        if (oppIds.isEmpty()) {
            return;
        }
        
        /*
        STEP 2
            Prevent duplicate log records
             */
        
        Set<Id> alreadyLoggedOpps =
            ResellerMappingSelector.getAlreadyLoggedOppIds(oppIds);
        
        /*
        STEP 3
            Create new log records
             */
        
        List<Reseller_Match_Log__c> logs = new List<Reseller_Match_Log__c>();
        
        for (Id oppId : oppIds) {
            
            if (alreadyLoggedOpps.contains(oppId)) {
                continue;
            }
            
            String email = emailByOpp.get(oppId);
            String domain = domainByOpp.get(oppId);
            
            Reseller_Match_Log__c log = new Reseller_Match_Log__c();
            
            log.Name = 'Unmatched - ' + email;
            log.Opportunity__c = oppId;
            log.Incoming_Email__c = email;
            log.Extracted_Domain__c = domain;
            
            if (String.isBlank(domain)) {
                log.Reason__c = 'Invalid Email';
            } else {
                log.Reason__c = 'No Mapping Found';
            }
            
            log.Created_From_Trigger__c = true;
            
            logs.add(log);
        }
        
        /*
        STEP 4
            Insert logs
             */
        
        if (!logs.isEmpty()) {
            insert logs;
        }
    }
}