/**
 * @description
 * <h2>Reseller Matching Engine</h2>
 *
 * Core business logic responsible for resolving the correct
 * <b>Reseller__c</b> for Opportunity records based on reseller email.
 *
 * This class does NOT perform:
 *
 * - Direct SOQL queries
 * - Email parsing logic
 *
 * These responsibilities are delegated to helper layers:
 *
 * EmailUtils               → email normalization & domain extraction
 * ResellerMappingSelector  → database queries
 *
 * -----------------------------------------------------------
 *
 * Architecture Flow
 *
 * Opportunity Trigger
 *        ↓
 * OpportunityResellerTriggerHandler
 *        ↓
 * ResellerMatchingEngine
 *        ↓
 * EmailUtils
 *        ↓
 * ResellerMappingSelector
 *        ↓
 * Reseller_Mapping__c
 *
 * -----------------------------------------------------------
 *
 * Matching Strategy
 *
 * 1. Normalize incoming email
 * 2. Attempt exact email match
 * 3. If not found → attempt domain match
 * 4. Assign Reseller__c if match exists
 *
 * -----------------------------------------------------------
 *
 * Bulk Safety
 *
 * All opportunities are processed in bulk.
 * Mapping lookups are cached using Maps for O(1) lookup.
 *
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class ResellerMatchingEngine {
    
    public static void matchBefore(List<Opportunity> opportunities) {
        
        if(opportunities == null || opportunities.isEmpty()){
            return;
        }
        
        Set<String> emails = new Set<String>();
        Set<String> domains = new Set<String>();
        
        Map<Opportunity,String> emailByOpp = new Map<Opportunity,String>();
        Map<Opportunity,String> domainByOpp = new Map<Opportunity,String>();
        
        /*
        STEP 1
            Collect normalized emails and domains
             */
        
        for(Opportunity opp : opportunities){
            
            String normalizedEmail = EmailUtils.normalizeEmail(opp.Reseller_Email__c);
            
            if(normalizedEmail == null){
                continue;
            }
            
            String domain = EmailUtils.extractDomain(normalizedEmail);
            
            emails.add(normalizedEmail);
            domains.add(domain);
            
            emailByOpp.put(opp, normalizedEmail);
            domainByOpp.put(opp, domain);
        }
        
        /*
        STEP 2
            Query mapping records
             */
        
        Map<String, Reseller_Mapping__c> emailMappings =
            ResellerMappingSelector.getMappings('Email', emails);
        
        Map<String, Reseller_Mapping__c> domainMappings =
            ResellerMappingSelector.getMappings('Domain', domains);
        
        /*
        STEP 3
            Apply matching logic
             */
        
        for(Opportunity opp : opportunities){
            
            String email = emailByOpp.get(opp);
            String domain = domainByOpp.get(opp);
            
            if(email == null){
                continue;
            }
            
            // EMAIL MATCH
            if(emailMappings.containsKey(email)){
                
                opp.Reseller__c =
                    emailMappings.get(email).Reseller__c;
                
                opp.Matched_By__c = 'Email';
                continue;
            }
            
            // DOMAIN FALLBACK
            if(domain != null && domainMappings.containsKey(domain)){
                
                opp.Reseller__c =
                    domainMappings.get(domain).Reseller__c;
                
                opp.Matched_By__c = 'Domain';
                continue;
            }
            
            opp.Matched_By__c = 'None';
        }
    }
}