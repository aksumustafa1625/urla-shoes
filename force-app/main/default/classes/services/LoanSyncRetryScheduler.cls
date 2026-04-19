/**
 * @description : Scheduled job that re-tries Loan__c records that have not yet
 *                been confirmed by the core system. Runs every 15 minutes by default.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 *
 * Design notes:
 * - Pulls up to 100 unsynced loans per tick (the 100-callouts-per-transaction limit
 *   puts a natural ceiling; LoanSyncService batches them into a single POST).
 * - Skips loans that have already retried MAX_RETRIES times — beyond that a human
 *   should look at Sync_Error__c + the Sync Log history.
 * - To schedule:
 *     System.schedule('Loan Sync Retry', '0 0,15,30,45 * * * ?', new LoanSyncRetryScheduler());
 */
public with sharing class LoanSyncRetryScheduler implements Schedulable {

    @TestVisible
    private static final Integer BATCH_LIMIT = 100;

    public void execute(SchedulableContext ctx) {
        runRetry();
    }

    /**
     * Same logic as execute() but callable directly — handy for manual retries
     * from anonymous Apex or a "Retry All" admin button.
     */
    public static void runRetry() {
        List<Loan__c> toRetry = [
            SELECT Id
            FROM Loan__c
            WHERE isSynced__c = false
              AND Retry_Count__c < :LoanSyncService.MAX_RETRIES
            ORDER BY Last_Sync_Attempt__c ASC NULLS FIRST
            LIMIT :BATCH_LIMIT
        ];

        if (toRetry.isEmpty()) {
            return;
        }

        List<Id> ids = new List<Id>();
        for (Loan__c l : toRetry) {
            ids.add(l.Id);
        }
        System.enqueueJob(new LoanSyncService(ids));
    }
}
