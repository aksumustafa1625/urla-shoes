/**
 * @description : Handles Loan__c creation on Opportunity. When an Opportunity transitions
 *                to StageName = 'Closed Won' (on insert OR update), a matching Loan__c
 *                record is created and queued for a sync callout to the core system.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @group       : Loan Creation
 *
 * Design notes:
 * - Extends the shared TriggerHandler framework (bypass + loop-count control).
 * - after insert / after update only — we need the Opportunity.Id to link the Loan,
 *   which is unavailable in before-insert.
 * - On update we compare against Trigger.oldMap so we fire ONCE per transition
 *   (not again on subsequent edits while the Opp stays Closed Won). Without this,
 *   any field change on a Closed-Won Opp would create a duplicate Loan.
 * - Business logic (loan construction, DML, async enqueue) lives in LoanCreationService
 *   so the handler stays thin and unit-testable in isolation.
 */
public with sharing class OpportunityLoanTriggerHandler extends TriggerHandler {

    // StageName value that triggers Loan creation. Pulled out as a constant so a
    // future rename (or org-specific picklist change) is a one-line fix.
    @TestVisible
    private static final String STAGE_CLOSED_WON = 'Closed Won';

    /**
     * After insert: any Opportunity inserted directly at Closed Won should get a Loan.
     * Rare in practice (most Opps start earlier in the funnel) but legitimate via
     * Data Loader / API, so we handle it.
     */
    protected override void afterInsert() {
        List<Opportunity> eligible = new List<Opportunity>();

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            if (isClosedWon(opp)) {
                eligible.add(opp);
            }
        }

        if (!eligible.isEmpty()) {
            LoanCreationService.createLoansForOpportunities(eligible);
        }
    }

    /**
     * After update: fire only on the transition INTO Closed Won, not on every
     * edit of an already-closed Opp. Without the oldMap compare, editing any field
     * on a Closed-Won Opportunity would spawn a duplicate Loan every time.
     */
    protected override void afterUpdate() {
        List<Opportunity> eligible = new List<Opportunity>();
        Map<Id, Opportunity> oldMap = (Map<Id, Opportunity>) Trigger.oldMap;

        for (Opportunity opp : (List<Opportunity>) Trigger.new) {
            Opportunity oldOpp = oldMap.get(opp.Id);
            // Transition = currently Closed Won AND previously something else.
            if (isClosedWon(opp) && !STAGE_CLOSED_WON.equalsIgnoreCase(oldOpp.StageName)) {
                eligible.add(opp);
            }
        }

        if (!eligible.isEmpty()) {
            LoanCreationService.createLoansForOpportunities(eligible);
        }
    }

    /**
     * Case-insensitive match so an org that stores 'closed won' or 'CLOSED WON'
     * (via a lazy import or historical data) still gets picked up.
     */
    @TestVisible
    private static Boolean isClosedWon(Opportunity opp) {
        return STAGE_CLOSED_WON.equalsIgnoreCase(opp.StageName);
    }
}
