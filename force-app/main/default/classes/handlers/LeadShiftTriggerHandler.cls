/**
 * LeadShiftTriggerHandler
 *
 * Purpose:
 * - Trigger handler (Kevin O'Hara pattern) for Lead object.
 * - On after insert, routes newly created Leads into the shift-based queue intake.
 *
 * Design:
 * - Extends base TriggerHandler to leverage standardized context routing and recursion guards.
 * - Delegates the heavy lifting to LeadQueueService to keep handler slim and testable.
 *
 * Notes:
 * - Must remain bulk-safe: always treat Trigger.new as a list.
 * - No DML/SOQL inside this method; service layer owns persistence and queries.
 *
 * Author: Mustafa Bey
 * Since: 2026
 */
public with sharing class LeadShiftTriggerHandler extends TriggerHandler {

    /**
     * Lifecycle: after insert (Lead)
     *
     * Behavior:
     * - Casts Trigger.new to List<Lead> and forwards to LeadQueueService for intake.
     * - Service is responsible for capacity checks, record preparation, and queue entry creation.
     */
    protected override void afterInsert() {

        // All records arriving in this context are the newly inserted Leads
        List<Lead> newLeads = (List<Lead>) Trigger.new;

        // Delegate to service to enqueue/process according to shift and capacity rules
        LeadQueueService.processNewLeads(newLeads);
    }
}
