/**
 * @description : Builds Loan__c records from Closed-Won Opportunities, inserts them,
 *                and enqueues the async sync callout to the core system.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 *
 * Design notes:
 * - Pure bulk pattern: one DML for the whole set, one Queueable for the whole set.
 * - Monthly payment is computed in Apex (not a formula field) so the value is frozen
 *   at creation time; a later change to Loan_Amount/Term should not silently drift.
 * - Division uses Decimal.divide(..., 2, RoundingMode.HALF_UP) to force 2-decimal
 *   precision — plain `/` on Decimal can throw on non-terminating quotients (e.g. 1/3).
 * - Opportunities missing Amount or Term_In_Months__c still produce a Loan, but with
 *   null monthly payment and null principal. This preserves the 1:1 Opp->Loan contract;
 *   data quality issues can be surfaced via reporting instead of silent drops.
 */
public with sharing class LoanCreationService {

    /**
     * @param opportunities Closed-Won Opportunities. Caller must filter; this method
     *                      does NOT re-check StageName, it trusts the handler.
     */
    public static void createLoansForOpportunities(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }

        // Re-query so we pick up the fields the trigger context may not have loaded
        // (Amount / Term_In_Months__c) regardless of what caused the trigger to fire.
        // Trigger.new in after-update only includes fields that were on the DML,
        // so a future-date call from a non-trigger path stays correct too.
        Set<Id> oppIds = new Map<Id, Opportunity>(opportunities).keySet();
        List<Opportunity> full = [
            SELECT Id, Amount, Term_In_Months__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ];

        List<Loan__c> toInsert = new List<Loan__c>();
        for (Opportunity opp : full) {
            toInsert.add(new Loan__c(
                Opportunity__c    = opp.Id,
                Loan_Amount__c    = opp.Amount,
                Term_In_Months__c = opp.Term_In_Months__c,
                Monthly_Payments__c = calculateMonthlyPayment(opp.Amount, opp.Term_In_Months__c),
                isSynced__c       = false
            ));
        }

        // Single DML for the entire batch keeps us far from the 150-statement limit.
        insert toInsert;

        // Collect the freshly-minted Ids and hand them to the async sync job.
        // One Queueable per trigger invocation (not per loan) to stay under the
        // 50-queueables-per-transaction limit on bulk loads.
        List<Id> loanIds = new List<Id>();
        for (Loan__c l : toInsert) {
            loanIds.add(l.Id);
        }
        if (!loanIds.isEmpty()) {
            System.enqueueJob(new LoanSyncService(loanIds));
        }
    }

    /**
     * Returns amount / term rounded to 2 decimals, or null if either input is
     * missing or the term is zero. Null is preferable to 0 here — 0 would
     * misrepresent an uncomputable payment as a valid figure.
     */
    @TestVisible
    private static Decimal calculateMonthlyPayment(Decimal amount, Decimal termInMonths) {
        if (amount == null || termInMonths == null || termInMonths == 0) {
            return null;
        }
        // HALF_UP matches typical finance rounding (2.345 -> 2.35).
        return amount.divide(termInMonths, 2, System.RoundingMode.HALF_UP);
    }
}
