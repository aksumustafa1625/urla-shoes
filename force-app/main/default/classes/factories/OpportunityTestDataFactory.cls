/**
 * @description
 * Centralized Test Data Factory used to generate reusable
 * test records for unit tests.
 *
 * This factory prevents duplication of test data creation
 * across multiple test classes.
 *
 * The class supports:
 *
 * - Account creation
 * - Reseller creation
 * - Opportunity generation
 * - Opportunity generation with reseller email
 * - Bulk opportunity generation
 *
 * Used for testing:
 *
 * ResellerMatchingEngine
 * ResellerMappingSelector
 * ResellerMatchLogService
 * OpportunityResellerTriggerHandler
 *
 * @author Mustafa Bey
 * @created 2026
 */
@isTest
public with sharing class OpportunityTestDataFactory {

    /**
     * Creates test Account
     */
    public static Account createAccount(Boolean doInsert){

        Account acc = new Account(
            Name = 'Test Account'
        );

        if(doInsert){
            insert acc;
        }

        return acc;
    }


    /**
     * Creates test Reseller
     */
    public static Reseller__c createReseller(Boolean doInsert){

        Reseller__c reseller = new Reseller__c(
            Name = 'Test Reseller',
            Company_Email__c = 'partner@test.com'
        );

        if(doInsert){
            insert reseller;
        }

        return reseller;
    }


    /**
     * Creates a basic test Opportunity
     */
    public static Opportunity createOpportunity(
        Id accountId,
        Boolean doInsert
    ){

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            AccountId = accountId
        );

        if(doInsert){
            insert opp;
        }

        return opp;
    }


    /**
     * Creates Opportunity with reseller email
     * Used specifically for testing reseller matching logic
     */
    public static Opportunity createOpportunityWithResellerEmail(
        Id accountId,
        String resellerEmail,
        Boolean doInsert
    ){

        Opportunity opp = new Opportunity(
            Name = 'Reseller Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(15),
            AccountId = accountId,
            Reseller_Email__c = resellerEmail
        );

        if(doInsert){
            insert opp;
        }

        return opp;
    }


    /**
     * Generates bulk opportunities for bulk testing
     */
    public static List<Opportunity> createBulkOpportunities(
        Id accountId,
        Integer amount
    ){

        List<Opportunity> opps = new List<Opportunity>();

        for(Integer i = 0; i < amount; i++){

            opps.add(new Opportunity(
                Name = 'Bulk Opportunity ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(10),
                AccountId = accountId,
                Reseller_Email__c = 'partner@test.com'
            ));
        }

        return opps;
    }

}




