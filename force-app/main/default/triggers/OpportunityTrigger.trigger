/**
 * @description : Trigger on Opportunity. Uses the thin-trigger pattern — no logic lives
 *                here; each concern is delegated to its own TriggerHandler subclass.
 *                Handlers run in the order below; order matters when earlier handlers
 *                mutate fields later ones read.
 * @author      : Mustafa Aksu
 * @date        : 2026-04-18
 * @events      : before insert, before update, after insert, after update
 *
 * Design notes:
 * - OpportunityResellerTriggerHandler runs first because it resolves Reseller__c in
 *   before-* contexts, giving downstream logic access to the resolved reseller.
 * - OpportunityLoanTriggerHandler only reacts in after-* contexts (it needs Opp.Id
 *   to link the Loan), so it cannot conflict with the reseller handler's before logic.
 */
trigger OpportunityTrigger on Opportunity (
    before insert,
    before update,
    after insert,
    after update
) {

    new OpportunityResellerTriggerHandler().run();
    new OpportunityLoanTriggerHandler().run();

}
