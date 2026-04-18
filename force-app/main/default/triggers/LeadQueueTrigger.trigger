/**
 * LeadQueueTrigger
 *
 * Purpose:
 * - Reacts to lifecycle events on Lead_Queue__c to coordinate queue processing.
 * - Delegates heavy logic to LeadQueueProcessor to keep trigger thin and bulk-safe.
 *
 * Context:
 * - Object: Lead_Queue__c (custom queue entries for lead assignment/processing)
 * - Events: after insert, after update, after delete
 *
 * Behavior Summary:
 * - After Insert: Process newly created Waiting entries to assign immediately if capacity exists.
 * - After Update: 
 *     * Periodically sweep/expire leads when entries change (e.g., status transitions).
 *     * When an entry is Completed with a Resolution, mirror that resolution to the related Lead.Status.
 *     * Collect just-completed entries to post-process (notifications/logging/etc.) in processor.
 * - After Delete: Clean up or reconcile state for removed entries.
 *
 * Notes:
 * - No SOQL/DML in loops beyond collected lists; uses lists and a single DML statement.
 * - Leave business rules inside LeadQueueProcessor to centralize queue logic.
 */
trigger LeadQueueTrigger on Lead_Queue__c (after insert, after update, after delete) {

    if (Trigger.isAfter && Trigger.isInsert) {
        // New Waiting record(s) arrived → if capacity allows, attempt immediate assignment
        // Processor is responsible for bulk-handling Trigger.new
        LeadQueueProcessor.processWaitingEntries(Trigger.new);
    }

    if (Trigger.isAfter && Trigger.isUpdate) {
        // Sweep for any leads that have expired due to SLA/time rules
        LeadQueueProcessor.processExpiredLeads();

        // Accumulators for safe, bulk DML outside of the loop
        List<Lead_Queue__c> completedEntries = new List<Lead_Queue__c>();
        List<Lead> leadsToUpdate = new List<Lead>();

        // Compare new vs old values to detect transitions and propagate outcomes
        for (Lead_Queue__c newEntry : Trigger.new) {
            Lead_Queue__c oldEntry = Trigger.oldMap.get(newEntry.Id);

            // Detect transition into Completed
            Boolean justCompleted = newEntry.Status__c == 'Completed'
                && oldEntry.Status__c != 'Completed';

            // If Completed and Resolution provided/changed, mirror to the underlying Lead.Status
            Boolean resolutionChanged = newEntry.Status__c == 'Completed'
                && String.isNotBlank(newEntry.Resolution__c)
                && newEntry.Resolution__c != oldEntry.Resolution__c;

            if (justCompleted) completedEntries.add(newEntry);

            if (resolutionChanged && newEntry.Lead__c != null) {
                // Mirror the resolution to Lead.Status via partial update (no read required)
                leadsToUpdate.add(new Lead(
                    Id     = newEntry.Lead__c,
                    Status = newEntry.Resolution__c
                ));
            }
        }

        // Single bulk DML outside the loop
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;

        // Post-process any entries that just became Completed (e.g., notifications/auditing)
        if (!completedEntries.isEmpty()) {
            LeadQueueProcessor.processCompletedEntries(completedEntries);
        }
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        // Reconcile queue state for deleted entries (e.g., free capacity, cleanup)
        LeadQueueProcessor.processDeletedEntries(Trigger.old);
    }
}
