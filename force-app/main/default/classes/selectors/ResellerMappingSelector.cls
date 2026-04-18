/**
 * @description
 * <h2>Reseller Mapping Selector</h2>
 *
 * Selector layer responsible for retrieving reseller mapping records
 * from Reseller_Mapping__c in a bulk-safe way.
 *
 * This class performs ONLY database access (SOQL).
 * It does not contain any matching or business logic.
 *
 * Mapping model:
 *
 * Mapping_Type__c  → Email / Domain
 * Value__c         → email or domain value
 * Reseller__c      → reseller lookup
 *
 * Example records:
 *
 * Email   → partner@bursa.com
 * Domain  → bursa.com
 *
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class ResellerMappingSelector {
    
    /**
     * Normalize string keys for map usage
     */
    private static String normalize(String value) {
        
        if (value == null) {
            return null;
        }
        
        return value.trim().toLowerCase();
    }
    
    
    /**
     * Get email mappings
     */
    public static Map<String, Reseller_Mapping__c> getEmailMappings(Set<String> emails) {
        
        Map<String, Reseller_Mapping__c> result = new Map<String, Reseller_Mapping__c>();
        
        if (emails == null || emails.isEmpty()) {
            return result;
        }
        
        List<Reseller_Mapping__c> mappings = [
            SELECT Id, Value__c, Reseller__c, Priority__c
            FROM Reseller_Mapping__c
            WHERE
                Mapping_Type__c = 'Email'
            AND Value__c IN :emails
            AND Is_Active__c = TRUE
        ];
        
        for (Reseller_Mapping__c m : mappings) {
            
            String key = normalize(m.Value__c);
            
            if (!result.containsKey(key)) {
                result.put(key, m);
            }
        }
        
        return result;
    }
    
    
    /**
     * Get domain mappings
     */
    public static Map<String, Reseller_Mapping__c> getDomainMappings(Set<String> domains) {
        
        Map<String, Reseller_Mapping__c> result = new Map<String, Reseller_Mapping__c>();
        
        if (domains == null || domains.isEmpty()) {
            return result;
        }
        
        List<Reseller_Mapping__c> mappings = [
            SELECT Id, Value__c, Reseller__c, Priority__c
            FROM Reseller_Mapping__c
            WHERE
                Mapping_Type__c = 'Domain'
            AND Value__c IN :domains
            AND Is_Active__c = TRUE
        ];
        
        for (Reseller_Mapping__c m : mappings) {
            
            String key = normalize(m.Value__c);
            
            if (!result.containsKey(key)) {
                result.put(key, m);
            }
        }
        
        return result;
    }
    
    public static Map<String, Reseller_Mapping__c> getMappings(
        String type,
    Set<String> values
    ){
        
        Map<String, Reseller_Mapping__c> result =
            new Map<String, Reseller_Mapping__c>();
        
        if(values.isEmpty()){
            return result;
        }
        
        for(Reseller_Mapping__c m : [
        SELECT Id,
               Value__c,
               Mapping_Type__c,
               Reseller__c,
               Priority__c,
               Is_Active__c
        FROM Reseller_Mapping__c
        WHERE Mapping_Type__c = :type
        AND Value__c IN :values
        AND Is_Active__c = true
        ORDER BY Priority__c DESC
    ]){
            
            String key = normalize(m.Value__c);
            
            if(!result.containsKey(key)){
                result.put(key, m);
            }
            
        }
        
        return result;
    }
    
    public static Set<Id> getAlreadyLoggedOppIds(Set<Id> oppIds){
        
        Set<Id> result = new Set<Id>();
        
        if(oppIds.isEmpty()){
            return result;
        }
        
        for(Reseller_Match_Log__c log : [
        SELECT Opportunity__c
        FROM Reseller_Match_Log__c
        WHERE Opportunity__c IN :oppIds
    ]){
            
            result.add(log.Opportunity__c);
            
        }
        
        return result;
    }
    
}