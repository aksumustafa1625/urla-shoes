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
trigger LeadQueueTrigger on Lead_Queue__c (before update, after insert, after update, after delete) {

    // Before Update: Rename entry when status transitions to Completed
    if (Trigger.isBefore && Trigger.isUpdate) {
        Set<Id> assigneeIds = new Set<Id>();
        for (Lead_Queue__c newEntry : Trigger.new) {
            Lead_Queue__c oldEntry = Trigger.oldMap.get(newEntry.Id);
            if (newEntry.Status__c == 'Completed'
                && oldEntry.Status__c != 'Completed'
                && newEntry.Assigned_To__c != null) {
                assigneeIds.add(newEntry.Assigned_To__c);
            }
        }

        if (!assigneeIds.isEmpty()) {
            Map<Id, String> userNames = new Map<Id, String>();
            for (User u : [SELECT Id, Name FROM User WHERE Id IN :assigneeIds]) {
                userNames.put(u.Id, u.Name);
            }

            for (Lead_Queue__c newEntry : Trigger.new) {
                Lead_Queue__c oldEntry = Trigger.oldMap.get(newEntry.Id);
                if (newEntry.Status__c == 'Completed'
                    && oldEntry.Status__c != 'Completed'
                    && newEntry.Assigned_To__c != null) {
                    String assignee = userNames.get(newEntry.Assigned_To__c);
                    newEntry.Name = 'LQ | ' + assignee + ' | Completed';
                }
            }
        }
    }

    if (Trigger.isAfter && Trigger.isInsert) {
        // New Waiting record(s) arrived → if capacity allows, attempt immediate assignment
        // Processor is responsible for bulk-handling Trigger.new
        LeadQueueProcessor.processWaitingEntries(Trigger.new);

        // Publish real-time event for dashboard refresh
        List<Lead_Shift_Event__e> events = new List<Lead_Shift_Event__e>();
        events.add(new Lead_Shift_Event__e(
            Event_Type__c = 'NewLead',
            Message__c = Trigger.new.size() + ' new lead(s) arrived'
        ));
        EventBus.publish(events);
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

            // Publish real-time events for each completion
            Set<Id> userIds = new Set<Id>();
            for (Lead_Queue__c e : completedEntries) {
                if (e.Assigned_To__c != null) userIds.add(e.Assigned_To__c);
            }
            Map<Id, String> userNames = new Map<Id, String>();
            if (!userIds.isEmpty()) {
                for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
                    userNames.put(u.Id, u.Name);
                }
            }

            List<Lead_Shift_Event__e> completedEvents = new List<Lead_Shift_Event__e>();
            for (Lead_Queue__c e : completedEntries) {
                String repName = e.Assigned_To__c != null && userNames.containsKey(e.Assigned_To__c)
                    ? userNames.get(e.Assigned_To__c) : 'Unknown';
                completedEvents.add(new Lead_Shift_Event__e(
                    Event_Type__c = 'Completed',
                    Rep_Name__c = repName,
                    Message__c = repName + ' completed a lead'
                ));
            }
            EventBus.publish(completedEvents);
        }
    }

    if (Trigger.isAfter && Trigger.isDelete) {
        // Reconcile queue state for deleted entries (e.g., free capacity, cleanup)
        LeadQueueProcessor.processDeletedEntries(Trigger.old);
    }
}
