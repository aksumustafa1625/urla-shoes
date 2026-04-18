/**
 * @description
 * Temporary data maintenance script used to reset Opportunity demo data
 * and generate new Opportunity records for reseller testing scenarios.
 *
 * This script performs the following steps:
 * 1. Deletes recently created Opportunity records with StageName = 'Prospecting'
 * 2. Generates new Opportunities for different reseller scenarios.
 *
 * This helps simulate reseller activity in the system and allows
 * testing of trigger logic, reseller lookup population and UI refresh.
 *
 * @author Mustafa Bey
 * @created 2026
 *
 * @warning
 * This script should only be executed in a sandbox or development org.
 * Running this in production may remove real Opportunity records.
 *
 * @example
 * Run using:
 * Right Click → Run Anonymous Apex
 */

delete [SELECT Id FROM Reseller_Match_Log__c];
delete [SELECT Id FROM Opportunity WHERE StageName = 'Prospecting' AND CreatedDate = LAST_N_DAYS:15];
delete [SELECT Id FROM Task];


OppCreationClass.createOpps('Bursa',2,'bursa@bursashop.com');
OppCreationClass.createOpps('Gemlik',6,'sales@bursagemlikshop.com');
OppCreationClass.createOpps('Nilüfer',8,'order@bursanilufershop.com');
OppCreationClass.createOpps('HotmailTest',9,'contact@hotmail.com');

OppCreationClass.createOpps('Kano',8,'kano@kanoshop.com');
OppCreationClass.createOpps('GmailTest',7,'buyer@gmail.com');

OppCreationClass.createOpps('Abuja',3,'abuja@abujashop.com');
OppCreationClass.createOpps('YahooTest',5,'sales@yahoo.com');

OppCreationClass.createOpps('IcloudTest',7,'mustafa.aksu@ntic.edu.ng');

Id resellerId = 'a07d3000007V5r7AAC'; // kendi reseller Id’nizi yazın

// Input oluştur
ResellerReconciliationService.ReconcileInput input =
    new ResellerReconciliationService.ReconcileInput();

input.resellerId = resellerId;

// Listeye koy (Invocable zorunlu)
List<ResellerReconciliationService.ReconcileInput> inputs =
new List<ResellerReconciliationService.ReconcileInput>{ input };

// Method çağır
ResellerReconciliationService.reconcile(inputs);