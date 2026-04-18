/**
 * LeadQueueService
 *
 * Purpose:
 * - Service layer that intakes newly created Leads and coordinates queueing/assignment.
 * - Assigns immediately when an active shift is available; otherwise enqueues as Waiting.
 *
 * Responsibilities:
 * - Prevent duplicate queue entries for the same Lead.
 * - Discover active shifts and select the next assignee via RoundRobinService.
 * - Create Lead_Queue__c entries and maintain SLA deadlines.
 * - Update Lead ownership on immediate assignment.
 *
 * Notes:
 * - Bulk-safe: processes lists; performs DML outside loops.
 * - Queries: limited to Users for display names when shifts are active.
 * - SLA: default 5 minutes (SLA_MINUTES) for immediate follow-up windows.
 *
 * Author: Mustafa Bey
 * Since: 2026
 */
public with sharing class LeadQueueService {
    
    // SLA window in minutes for assigned leads to be actioned
    private static final Integer SLA_MINUTES = 5;
    
    /**
     * Entry point from LeadShiftTriggerHandler.
     *
     * Behavior:
     * - Guards against null/empty input.
     * - Filters out already-queued leads.
     * - Retrieves active shifts and prepares a map of assignee display names.
     * - For each lead: constructs a queue entry and either assigns immediately (with SLA and owner update)
     *   or marks as Waiting when no capacity or selection is not possible.
     * - Commits queue entries and batched lead ownership updates in bulk.
     *
     * Bulkification:
     * - Aggregates DML for queue entries and lead updates.
     */
    public static void processNewLeads(List<Lead> leads) {
        
        if (leads == null || leads.isEmpty()) {
            return;
        }
        
        // Prevent duplicate queue entries by checking existing queued lead ids
        Set<Id> leadIds = new Set<Id>();
        for (Lead l : leads) {
            leadIds.add(l.Id);
        }
        
        Set<Id> alreadyQueued =
            ShiftSelector.getAlreadyQueuedLeadIds(leadIds);
        
        // Get currently active shifts (capacity providers)
        List<Shift__c> activeShifts =
            ShiftSelector.getActiveShifts();
        
        // Collect user IDs from active shifts to fetch human-readable names for labeling
        Set<Id> shiftUserIds = new Set<Id>();
        for (Shift__c s : activeShifts) {
            if (s.Assigned_User__c != null) {
                shiftUserIds.add(s.Assigned_User__c);
            }
        }
        
        Map<Id, String> userNameMap = new Map<Id, String>();
        if (!shiftUserIds.isEmpty()) {
            for (User u : [
        SELECT Id, Name
        FROM User
        WHERE Id IN :shiftUserIds
        AND UserType = 'Standard'
        AND IsActive = true
    ]) {
                userNameMap.put(u.Id, u.Name);
            }
        }
        
        // Accumulators for bulk DML
        List<Lead_Queue__c> queueEntries =
            new List<Lead_Queue__c>();
        
        List<Lead> leadsToUpdate = new List<Lead>();
        
        for (Lead lead : leads) {
            
            if (alreadyQueued.contains(lead.Id)) {
                // Skip leads that are already represented in the queue
                continue;
            }
            
            // Build readable lead full name for queue record naming
            String leadFullName =
                (lead.FirstName != null ? lead.FirstName + ' ' : '')
                + (lead.LastName != null ? lead.LastName : 'Unknown');
            
            Lead_Queue__c entry = new Lead_Queue__c();
            entry.Lead__c             = lead.Id;
            entry.Queue_Entry_Time__c = DateTime.now();
            entry.Priority__c         = getPriority(lead);
            
            if (!activeShifts.isEmpty()) {
                
                // Select next shift holder using round-robin
                Shift__c selectedShift =
                    RoundRobinService.getNextShift(activeShifts);
                
                if (selectedShift != null
                && userNameMap.containsKey(selectedShift.Assigned_User__c)) {
                    
                    String assigneeName =
                        userNameMap.get(selectedShift.Assigned_User__c);
                    
                    // Immediate assignment path
                    entry.Name            = 'LQ | ' + assigneeName + ' | ' + leadFullName;
                    entry.Status__c       = 'Assigned';
                    entry.Assigned_To__c  = selectedShift.Assigned_User__c;
                    entry.Assigned_At__c  = DateTime.now();
                    entry.SLA_Deadline__c = DateTime.now().addMinutes(SLA_MINUTES);
                    
                    // Update lead owner to reflect assignment
                    Lead leadToUpdate = new Lead(Id = lead.Id);
                    leadToUpdate.OwnerId = selectedShift.Assigned_User__c;
                    leadsToUpdate.add(leadToUpdate);
                    
                    // Increment shift lead count for monitoring/next selection fairness
                    RoundRobinService.incrementLeadCount(
                        selectedShift.Id
                        );
                    
                    // Remove from active shifts list for this iteration to distribute fairly
                    activeShifts.remove(
                        activeShifts.indexOf(selectedShift)
                        );
                    
                } else {
                    // Fallback when no valid assignee name mapping exists
                    entry.Name      = 'LQ | Waiting | ' + leadFullName;
                    entry.Status__c = 'Waiting';
                }
                
            } else {
                // No active shift → add to waiting queue
                entry.Name      = 'LQ | Waiting | ' + leadFullName;
                entry.Status__c = 'Waiting';
            }
            
            queueEntries.add(entry);
        }
        
        // Commit created queue entries
        if (!queueEntries.isEmpty()) {
            insert queueEntries;
        }
        
        // Commit owner updates in bulk
        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
    
    /**
     * Computes a simple numeric priority for a Lead.
     *
     * Heuristic:
     * - Rating 'Hot' => 1 (highest)
     * - Rating 'Warm' => 2
     * - LeadSource 'Phone' => 1 (treat phone as urgent)
     * - LeadSource 'Web' => 3
     * - Default => 5 (lowest)
     */
    private static Integer getPriority(Lead lead) {
        
        if (lead.Rating == 'Hot')        return 1;
        if (lead.Rating == 'Warm')       return 2;
        if (lead.LeadSource == 'Phone')  return 1;
        if (lead.LeadSource == 'Web')    return 3;
        
        return 5;
    }
}
