/**
 * @description
 * <h2>Opportunity Test Data Generator</h2>
 *
 * Utility class used to generate Opportunity records dynamically.
 * This class is useful for:
 *
 * - Testing reseller matching logic
 * - Populating demo environments
 * - Simulating inbound reseller emails
 * - Trigger and engine validation
 *
 * The class inserts Opportunity records with the
 * <b>Reseller_Email__c</b> field populated so the
 * reseller matching engine can execute.
 *
 * ------------------------------------------------------------------
 * Example Usage
 * ------------------------------------------------------------------
 *
 * OppCreationClass.createOpps('Bursa', 5, 'sales@bursashop.com');
 *
 * Result:
 * 5 Opportunities will be created:
 *
 * Bursa Opp 0
 * Bursa Opp 1
 * Bursa Opp 2
 * Bursa Opp 3
 * Bursa Opp 4
 *
 * ------------------------------------------------------------------
 *
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class OppCreationClass {
    
    public static void createOpps(
        String cityPrefix,
        Integer amount,
        String resellerEmail
    ) {
        
        if (amount == null || amount <= 0) {
            System.debug('Invalid amount provided.');
            return;
        }
        
        List<Opportunity> opps = new List<Opportunity>();
        
        for (Integer i = 0; i < amount; i++) {
            
            Opportunity opp = new Opportunity(
                Name = cityPrefix + ' Opp ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Reseller_Email__c = resellerEmail
            );
            
            opps.add(opp);
        }
        
        // 🔥 1️⃣ Önce Opportunity insert edilir
        insert opps;
        
        // // 🔥 2️⃣ Sonra Task oluşturulur (ID artık var)
        // TaskCreationService.createTasksForOpportunities(opps);
        
        System.debug(
            'OppCreationClass → Created Opportunities: ' + opps.size()
        );
    }
}