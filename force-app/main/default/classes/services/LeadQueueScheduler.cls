/**
 * LeadQueueScheduler
 *
 * Purpose:
 * - Time-based coordinator that keeps the Lead queue healthy.
 * - Runs every 5 minutes to reassign expired leads and attempt assignment of Waiting leads.
 *
 * Responsibilities:
 * - processExpiredLeads(): Return Assigned entries past SLA deadline back to Waiting and
 *   decrement the previous assignee's shift count.
 * - processWaitingLeads(): Assign oldest/highest-priority Waiting leads to currently active shifts.
 * - scheduleNext(): Self-reschedule pattern for continuous execution.
 *
 * Notes:
 * - Bulk-safe DML: Updates are batched outside of loops.
 * - Priority order: Waiting entries ordered by Priority then Queue_Entry_Time__c.
 * - Uses RoundRobinService to fairly distribute assignments.
 *
 * Author: Mustafa Bey
 * Since: 2026
 */
global with sharing class LeadQueueScheduler implements Schedulable {
    
    global void execute(SchedulableContext sc) {
        
        // Step 1: Move past-SLA Assigned entries back to Waiting and adjust shift counters
        processExpiredLeads();
        
        // Step 2: Assign Waiting leads if there are active shifts available
        processWaitingLeads();
        
        // Re-schedule itself to run again in ~5 minutes
        scheduleNext();
    }
    
    /**
     * Returns Assigned leads that missed their SLA back to Waiting
     * and reduces the previous shift's lead counter.
     */
    private void processExpiredLeads() {
        
        List<Lead_Queue__c> expired = [
            SELECT Id, Lead__c, Assigned_To__c,
                   Priority__c, Queue_Entry_Time__c,
                   Name  
            FROM Lead_Queue__c
            WHERE Status__c = 'Assigned'
            AND SLA_Deadline__c < :DateTime.now()
];
        
        if (expired.isEmpty()) return;
        
        // Gather previous assignee user IDs to decrement their shift counts
        Set<Id> oldUserIds = new Set<Id>();
        for (Lead_Queue__c lq : expired) {
            if (lq.Assigned_To__c != null) {
                oldUserIds.add(lq.Assigned_To__c);
            }
        }
        
        List<Shift__c> oldShifts = [
            SELECT Id, Current_Lead_Count__c, Assigned_User__c
            FROM Shift__c
            WHERE Assigned_User__c IN :oldUserIds
        ];
        
        for (Shift__c s : oldShifts) {
            if (s.Current_Lead_Count__c != null
            && s.Current_Lead_Count__c > 0) {
                s.Current_Lead_Count__c -= 1;
            }
        }
        
        if (!oldShifts.isEmpty()) update oldShifts;
        
        // Transition expired entries back to Waiting with updated labels
        List<Lead_Queue__c> toWaiting = new List<Lead_Queue__c>();
        for (Lead_Queue__c lq : expired) {
            lq.Status__c       = 'Waiting';
            lq.Assigned_To__c  = null;
            lq.Assigned_At__c  = null;
            lq.SLA_Deadline__c = null;
            String leadName = lq.Name != null
                ? lq.Name.substringAfterLast('| ')
                : 'Unknown';
            lq.Name = 'LQ | Reassigning | ' + leadName;
            toWaiting.add(lq);
        }
        
        update toWaiting;
    }
    
    /**
     * Assigns Waiting leads to active, capacity-eligible shifts.
     */
    private void processWaitingLeads() {
        
        List<Lead_Queue__c> waiting = [
            SELECT Id, Lead__c, Priority__c, Queue_Entry_Time__c
            FROM Lead_Queue__c
            WHERE Status__c = 'Waiting'
            ORDER BY Priority__c ASC, Queue_Entry_Time__c ASC
        ];
        
        if (waiting.isEmpty()) return;
        
        List<Shift__c> availableShifts =
            ShiftSelector.getActiveShifts();
        
        if (availableShifts.isEmpty()) return;
        
        // Prefetch user display names for nicer queue record labels
        Set<Id> userIds = new Set<Id>();
        for (Shift__c s : availableShifts) {
            userIds.add(s.Assigned_User__c);
        }
        Map<Id, String> userNameMap = new Map<Id, String>();
        for (User u : [
            SELECT Id, Name FROM User WHERE Id IN :userIds
        ]) {
            userNameMap.put(u.Id, u.Name);
        }
        
        // Prefetch lead names used for label composition
        Set<Id> leadIds = new Set<Id>();
        for (Lead_Queue__c lq : waiting) leadIds.add(lq.Lead__c);
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, FirstName, LastName
            FROM Lead WHERE Id IN :leadIds
        ]);
        
        List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
        List<Lead> leadsToUpdate     = new List<Lead>();
        
        for (Lead_Queue__c lq : waiting) {
            
            if (availableShifts.isEmpty()) break;
            
            Shift__c selectedShift =
                RoundRobinService.getNextShift(availableShifts);
            
            if (selectedShift == null) break;
            
            Lead lead = leadMap.get(lq.Lead__c);
            String leadFullName = lead != null
                ? ((lead.FirstName != null
                ? lead.FirstName + ' ' : '')
                + (lead.LastName != null
                ? lead.LastName : 'Unknown'))
                : 'Unknown';
            
            String assigneeName =
                userNameMap.get(selectedShift.Assigned_User__c);
            
            // Immediate assignment of a Waiting entry
            lq.Name            = 'LQ | ' + assigneeName
                + ' | ' + leadFullName;
            lq.Status__c       = 'Assigned';
            lq.Assigned_To__c  = selectedShift.Assigned_User__c;
            lq.Assigned_At__c  = DateTime.now();
            lq.SLA_Deadline__c = DateTime.now().addMinutes(5);
            toUpdate.add(lq);
            
            // Reflect ownership on the underlying Lead
            leadsToUpdate.add(new Lead(
                Id      = lq.Lead__c,
            OwnerId = selectedShift.Assigned_User__c
                ));
            
            // Keep round-robin counters accurate
            RoundRobinService.incrementLeadCount(selectedShift.Id);
            
            // Remove the shift from the pool so the next lead goes to a different user
            availableShifts.remove(availableShifts.indexOf(selectedShift));
        }
        
        if (!toUpdate.isEmpty()) update toUpdate;
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
    }
    
    /**
     * Self-reschedules to run again 5 minutes later.
     */
    public static void scheduleNext() {
        
        List<CronTrigger> oldJobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE 'LeadQueueScheduler_%'
            AND State IN ('COMPLETE', 'DELETED', 'ERROR')
        ];
        if (!oldJobs.isEmpty()) {
            for (CronTrigger ct : oldJobs) {
                System.abortJob(ct.Id);
            }
        }
        
        DateTime next    = DateTime.now().addMinutes(5);
        String jobName   = 'LeadQueueScheduler_' + next.getTime();
        
        String cron = '0 '
            + next.minute() + ' '
            + next.hour()   + ' '
            + next.day()    + ' '
            + next.month()  + ' ? '
            + next.year();
        
        System.schedule(jobName, cron, new LeadQueueScheduler());
    }
    
    /**
     * Bootstrap once via Execute Anonymous:
     * LeadQueueScheduler.startScheduler();
     */
    public static void startScheduler() {
        
        DateTime next  = DateTime.now().addMinutes(1);
        String jobName = 'LeadQueueScheduler_' + next.getTime();
        
        String cron = '0 '
            + next.minute() + ' '
            + next.hour()   + ' '
            + next.day()    + ' '
            + next.month()  + ' ? '
            + next.year();
        
        System.schedule(jobName, cron, new LeadQueueScheduler());
    }
}
