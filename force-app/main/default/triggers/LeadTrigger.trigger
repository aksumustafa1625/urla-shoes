/**
 * LeadTrigger
 * 
 * Purpose:
 * - Executes post-insert logic for Lead records.
 * - Delegates business logic to LeadShiftTriggerHandler to keep trigger lean and maintainable.
 *
 * Context:
 * - Events: after insert
 * - Bulkification: Handler must be bulk-safe. This trigger performs no per-record work.
 *
 * Notes:
 * - Avoid adding business logic here; extend behavior inside LeadShiftTriggerHandler instead.
 * - Ensure handler adheres to one-transaction, no DML/SOQL in loops best practices.
 */
trigger LeadTrigger on Lead (after insert) {
    // Delegate all after-insert processing (e.g., shift assignment or related post-processing)
    // to the dedicated handler. The handler is expected to process Trigger.new as a collection.
    new LeadShiftTriggerHandler().run();
}
