/**
 * @description
 * <h2>Opportunity Reseller Trigger Handler</h2>
 *
 * This handler resolves the correct <b>Reseller__c</b> for Opportunity
 * records based on the reseller email provided on the Opportunity.
 *
 * The class extends the <b>Kevin O'Hara TriggerHandler framework</b>
 * and overrides relevant trigger lifecycle methods.
 *
 * -----------------------------------------------------------------------
 * Architecture Flow
 * -----------------------------------------------------------------------
 *
 * Opportunity Trigger
 *        │
 *        ▼
 * OpportunityResellerTriggerHandler
 *        │
 *        ▼
 * ResellerMatchingEngine
 *        │
 *        ▼
 * EmailUtils + ResellerMappingSelector
 *        │
 *        ▼
 * Reseller_Mapping__c
 *
 * -----------------------------------------------------------------------
 * Matching Strategy
 * -----------------------------------------------------------------------
 *
 * 1. Email normalization using EmailUtils
 * 2. Exact email match using Reseller_Mapping__c
 * 3. Domain fallback match if email match fails
 * 4. Create diagnostic log if reseller remains unresolved
 *
 * -----------------------------------------------------------------------
 * Responsibilities
 * -----------------------------------------------------------------------
 *
 * TriggerHandler               → manages trigger lifecycle
 * ResellerMatchingEngine       → contains matching logic
 * ResellerMappingSelector      → performs database queries
 * EmailUtils                   → parses and normalizes email values
 * ResellerMatchLogService      → logs unmatched opportunities
 *
 * -----------------------------------------------------------------------
 * Trigger Context Behavior
 * -----------------------------------------------------------------------
 *
 * BEFORE INSERT  → Resolve reseller before record save
 * BEFORE UPDATE  → Re-evaluate reseller when email changes
 * AFTER INSERT   → Create unmatched log records
 * AFTER UPDATE   → Create unmatched log records if unresolved
 *
 * @framework Kevin O'Hara Trigger Framework
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class OpportunityResellerTriggerHandler extends TriggerHandler {
    
    /**
     * @description
     * BEFORE INSERT
     *
     * Resolves reseller before the Opportunity record
     * is saved to the database.
     *
     * Delegates matching logic to:
     * ResellerMatchingEngine
     *
     * @example
     * Incoming Opportunity
     * Reseller_Email__c = partner@bursa.com
     *
     * Result
     * Reseller__c = Bursa Reseller
     */
    protected override void beforeInsert() {
        
        List<Opportunity> newOpps = (List<Opportunity>) Trigger.new;
        
        ResellerMatchingEngine.matchBefore(newOpps);
    }
    
    
    /**
     * @description
     * BEFORE UPDATE
     *
     * Re-evaluates reseller resolution when the reseller
     * email field is modified.
     *
     * Delegates matching logic to:
     * ResellerMatchingEngine
     *
     * @param Trigger.new Updated Opportunity records
     */
    protected override void beforeUpdate() {
        
        List<Opportunity> newOpps = (List<Opportunity>) Trigger.new;
        
        ResellerMatchingEngine.matchBefore(newOpps);
    }
    
    
    /**
     * @description
     * AFTER INSERT
     *
     * Creates diagnostic log records for Opportunities
     * where a reseller could not be resolved.
     *
     * Delegates logging to:
     * ResellerMatchLogService
     *
     * @param Trigger.new Newly created Opportunities
     */
    protected override void afterInsert() {
        
        List<Opportunity> newOpps = (List<Opportunity>) Trigger.new;
        
        ResellerMatchLogService.createLogsAfter(newOpps);
        
        Set<String> domainsToEmail = new Set<String>();
        
        for (Opportunity opp : newOpps) {
            
            if (opp.Reseller__c != null) {
                continue;
            }
            
            if (String.isBlank(opp.Reseller_Email__c)) {
                continue;
            }
            
            String domain = EmailUtils.extractDomain(opp.Reseller_Email__c);
            
            if (domain != null) {
                domainsToEmail.add(domain);
            }
        }
        
        for (String domain : domainsToEmail) {
            
                Boolean shouldSend =
                    PartnerRegistrationEmailService.shouldSendRegistrationEmail(domain);
            
                if (shouldSend) {
                
                        String email = 'mustafa.aksu@ntic.edu.ng';
                
                        PartnerRegistrationEmailService.sendRegistrationEmail(email);
                }
        }
    }
    
    
    /**
     * @description
     * AFTER UPDATE
     *
     * Creates diagnostic log records when an Opportunity
     * still has no resolved reseller after update.
     *
     * Delegates logging to:
     * ResellerMatchLogService
     *
     * @param Trigger.new Updated Opportunities
     */
    protected override void afterUpdate() {
        
        List<Opportunity> newOpps = (List<Opportunity>) Trigger.new;
        
        ResellerMatchLogService.createLogsAfter(newOpps);
        
        Set<String> processedDomains = new Set<String>();
        
        for (Opportunity opp : newOpps) {
            
            // EKLENEN KISIM BURASI: 
            // Eğer Reseller zaten atanmışsa (form doldurulup eşleşme yapıldıysa), 
            // bu Opportunity için tekrar mail gönderme işlemini atla.
            if (opp.Reseller__c != null) {
                continue;
            }
            
            if (String.isBlank(opp.Reseller_Email__c)) {
                continue;
            }
            
            String domain = EmailUtils.extractDomain(opp.Reseller_Email__c);
            
            if (processedDomains.contains(domain)) {
                continue;
            }
            
            Boolean shouldSend =
                PartnerRegistrationEmailService.shouldSendRegistrationEmail(domain);
            
            if (shouldSend) {
                
                PartnerRegistrationEmailService.sendRegistrationEmail(
                    opp.Reseller_Email__c
                    );
                
                processedDomains.add(domain);
            }
        }
        
    }
    
}