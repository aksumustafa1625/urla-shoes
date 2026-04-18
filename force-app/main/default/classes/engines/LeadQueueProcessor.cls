/**
 * LeadQueueProcessor
 * ------------------
 * Purpose:
 *   Orchestrates assignment and re-assignment of Lead_Queue__c entries to active Shifts and Users.
 *   Implements core queue processing use cases:
 *     - Assign "Waiting" queue entries to reps in active shifts via round-robin
 *     - Decrement shift load when entries complete or are deleted
 *     - Reclaim expired assignments (SLA breach) back to "Waiting" and log breaches
 *
 * Key Concepts:
 *   - Shift__c tracks capacity and current load per rep (Assigned_User__c)
 *   - RoundRobinService decides next shift to receive a lead and updates per-shift counters
 *   - Status__c on Lead_Queue__c drives state machine: Waiting -> Assigned -> (Completed | Expired -> Waiting)
 *
 * Governor Considerations:
 *   - Bulk-safe: accepts Lists, batches SOQL by ids, and performs DML in bulk
 *   - Limits: keeps per-transaction SOQL/DML minimal; removes full shifts when capacity reached to avoid extra checks
 *
 * Notes:
 *   - SLA expired handling logs SLA_Breach_Log__c and frees capacity
 *   - The method processWaitingEntriesExcluding(...) prevents assigning back to recently expired reps
 *
 * Testing Tips:
 *   - Seed Shift__c records with capacity and mark as active; assert round-robin distribution.
 *   - Create Lead_Queue__c with various states and verify transitions + counter updates.
 *   - Simulate SLA expiry by backdating SLA_Deadline__c and assert breach log creation.
 */
public with sharing class LeadQueueProcessor {

    // Guard flag to prevent re-entrancy in processExpiredLeads within the same transaction
    private static Boolean expiredAlreadyRan = false;

    /**
     * Assigns "Waiting" Lead_Queue__c entries to available active shifts using round-robin.
     *
     * @param newEntries List of newly inserted or pending Lead_Queue__c records to evaluate.
     *                   Only entries with Status__c = 'Waiting' are assigned.
     * Behavior:
     *   - Fetches active shifts; exits early if none
     *   - Builds Lead names and assignee names for display Name
     *   - Uses RoundRobinService to select the next shift and increments shift load
     *   - Updates both Lead_Queue__c and Lead.OwnerId in bulk
     */
    /**
     * Assigns newly inserted or existing "Waiting" queue entries to active shifts fairly.
     * Exits fast when there are no active shifts. Prefetches Users and Leads for label building.
     */
    public static void processWaitingEntries(List<Lead_Queue__c> newEntries) {
        if (newEntries == null || newEntries.isEmpty()) return;

        List<Shift__c> availableShifts = ShiftSelector.getActiveShifts();
        if (availableShifts.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Lead_Queue__c lq : newEntries) {
            if (lq.Lead__c != null) leadIds.add(lq.Lead__c);
        }

        // Preload Leads for display name composition; avoids repeated queries in the loop
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, FirstName, LastName FROM Lead WHERE Id IN :leadIds
        ]);

        Set<Id> userIds = new Set<Id>();
        for (Shift__c s : availableShifts) userIds.add(s.Assigned_User__c);
        Map<Id, String> userNameMap = new Map<Id, String>();
        // Preload User display names for Assigned_To__c users
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
            userNameMap.put(u.Id, u.Name);
        }

        List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead_Queue__c lq : newEntries) {
            if (availableShifts.isEmpty()) break;
            if (lq.Status__c != 'Waiting') continue;

            // Choose next shift via round-robin; may be null if capacity fully drained
            Shift__c selectedShift = RoundRobinService.getNextShift(availableShifts);
            if (selectedShift == null) break;

            Lead lead = leadMap.get(lq.Lead__c);
            String leadFullName = lead != null
                ? ((lead.FirstName != null ? lead.FirstName + ' ' : '')
                    + (lead.LastName != null ? lead.LastName : 'Unknown'))
                : 'Unknown';

            String assigneeName = userNameMap.get(selectedShift.Assigned_User__c);

            toUpdate.add(new Lead_Queue__c(
                Id              = lq.Id,
                Name            = 'LQ | ' + assigneeName + ' | ' + leadFullName,
                Status__c       = 'Assigned',
                Assigned_To__c  = selectedShift.Assigned_User__c,
                Assigned_At__c  = DateTime.now(),
                SLA_Deadline__c = DateTime.now().addMinutes(5)
            ));

            leadsToUpdate.add(new Lead(
                Id      = lq.Lead__c,
                OwnerId = selectedShift.Assigned_User__c
            ));

            // Keep in-memory count in sync to make capacity checks reliable in this transaction
            selectedShift.Current_Lead_Count__c =
                (selectedShift.Current_Lead_Count__c != null
                ? selectedShift.Current_Lead_Count__c : 0) + 1;

            RoundRobinService.incrementLeadCount(selectedShift.Id);

            // Remove the shift from local pool when it reaches capacity to avoid over-assignment
            if (selectedShift.Current_Lead_Count__c >= selectedShift.Max_Capacity__c) {
                availableShifts.remove(availableShifts.indexOf(selectedShift));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
    }

    /**
     * Handles entries that transitioned to a "completed" terminal state outside this class.
     * Decrements the Current_Lead_Count__c on the corresponding active shifts and
     * then tries to backfill new "Waiting" entries up to a small batch.
     *
     * @param completedEntries Lead_Queue__c records that have just completed.
     */
    /**
     * Decrements shift counters for just-completed entries and backfills capacity
     * by assigning a small batch of oldest Waiting entries.
     */
    public static void processCompletedEntries(List<Lead_Queue__c> completedEntries) {
        if (completedEntries == null || completedEntries.isEmpty()) return;

        Set<Id> assignedUserIds = new Set<Id>();
        for (Lead_Queue__c entry : completedEntries) {
            if (entry.Assigned_To__c != null) assignedUserIds.add(entry.Assigned_To__c);
        }

        if (assignedUserIds.isEmpty()) return;

        // Pull active shifts for the affected users and decrement their current load
        List<Shift__c> shiftsToUpdate = [
            SELECT Id, Current_Lead_Count__c, Assigned_User__c,
                   Timezone__c, Start_Hour__c, End_Hour__c,
                   Is_Active__c, Max_Capacity__c
            FROM Shift__c
            WHERE Assigned_User__c IN :assignedUserIds
            AND Is_Active__c = true
        ];

        List<Shift__c> decrementedShifts = new List<Shift__c>();
        for (Shift__c shift : shiftsToUpdate) {
            if (shift.Current_Lead_Count__c != null && shift.Current_Lead_Count__c > 0) {
                shift.Current_Lead_Count__c -= 1;
                decrementedShifts.add(shift);
            }
        }

        if (!decrementedShifts.isEmpty()) update decrementedShifts;

        // Fetch a small batch of oldest "Waiting" entries to backfill capacity
        List<Lead_Queue__c> waitingEntries = [
            SELECT Id, Lead__c, Priority__c, Status__c
            FROM Lead_Queue__c
            WHERE Status__c = 'Waiting'
            ORDER BY Queue_Entry_Time__c ASC NULLS LAST
            LIMIT 10
        ];

        if (waitingEntries.isEmpty()) return;

        List<Shift__c> availableShifts = ShiftSelector.getActiveShifts();
        if (availableShifts.isEmpty()) return;

        Set<Id> waitingLeadIds = new Set<Id>();
        for (Lead_Queue__c wq : waitingEntries) waitingLeadIds.add(wq.Lead__c);

        // Preload lead names for display purposes
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, FirstName, LastName FROM Lead WHERE Id IN :waitingLeadIds
        ]);

        Set<Id> shiftUserIds = new Set<Id>();
        for (Shift__c s : availableShifts) shiftUserIds.add(s.Assigned_User__c);
        Map<Id, String> userNameMap = new Map<Id, String>();
        // Preload assignee names
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :shiftUserIds]) {
            userNameMap.put(u.Id, u.Name);
        }

        List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead_Queue__c waiting : waitingEntries) {
            if (availableShifts.isEmpty()) break;

            // Assign next waiting entry to the next available shift
            Shift__c selectedShift = RoundRobinService.getNextShift(availableShifts);
            if (selectedShift == null) break;

            Lead lead = leadMap.get(waiting.Lead__c);
            String leadFullName = lead != null
                ? ((lead.FirstName != null ? lead.FirstName + ' ' : '')
                    + (lead.LastName != null ? lead.LastName : 'Unknown'))
                : 'Unknown';

            String assigneeName = userNameMap.get(selectedShift.Assigned_User__c);

            waiting.Name            = 'LQ | ' + assigneeName + ' | ' + leadFullName;
            waiting.Status__c       = 'Assigned';
            waiting.Assigned_To__c  = selectedShift.Assigned_User__c;
            waiting.Assigned_At__c  = DateTime.now();
            waiting.SLA_Deadline__c = DateTime.now().addMinutes(5);

            toUpdate.add(waiting);
            leadsToUpdate.add(new Lead(Id = waiting.Lead__c, OwnerId = selectedShift.Assigned_User__c));

            // Mirror count locally and via RoundRobinService
            selectedShift.Current_Lead_Count__c =
                (selectedShift.Current_Lead_Count__c != null
                ? selectedShift.Current_Lead_Count__c : 0) + 1;

            RoundRobinService.incrementLeadCount(selectedShift.Id);

            if (selectedShift.Current_Lead_Count__c >= selectedShift.Max_Capacity__c) {
                availableShifts.remove(availableShifts.indexOf(selectedShift));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
    }

    /**
     * Reclaims "Assigned" entries whose SLA_Deadline__c has elapsed.
     * - Logs SLA_Breach_Log__c entries per expired record
     * - Decrements shift load for the previously assigned reps
     * - Resets Lead_Queue__c back to "Waiting" and re-queues
     * - Optionally triggers reassignment excluding recently expired reps to diversify distribution
     *
     * Guarded by expiredAlreadyRan to avoid accidental recursion in a single transaction.
     */
    /**
     * Sweeps for assignments past their SLA deadline and returns them to Waiting.
     * Also emits SLA_Breach_Log__c for auditability and attempts fair reassignment excluding
     * the breaching reps within this transaction.
     */
    public static void processExpiredLeads() {
        if (expiredAlreadyRan) return;
        expiredAlreadyRan = true;

        DateTime now = DateTime.now();

        // Find all assignments past their SLA deadline
        List<Lead_Queue__c> expiredEntries = [
            SELECT Id, Name, Assigned_To__c, Assigned_At__c,
                   SLA_Deadline__c, Status__c, Lead__c
            FROM Lead_Queue__c
            WHERE Status__c = 'Assigned'
            AND SLA_Deadline__c <= :now
        ];

        System.debug('>>> Expired bulunan: ' + expiredEntries.size());
        if (expiredEntries.isEmpty()) return;

        Set<Id> expiredUserIds = new Set<Id>();
        for (Lead_Queue__c entry : expiredEntries) {
            if (entry.Assigned_To__c != null) expiredUserIds.add(entry.Assigned_To__c);
        }

        List<Shift__c> shiftsToDecrement = [
            SELECT Id, Current_Lead_Count__c, Assigned_User__c
            FROM Shift__c
            WHERE Assigned_User__c IN :expiredUserIds
            AND Is_Active__c = true
        ];

        // Decrement load for reps with expired assignments
        for (Shift__c s : shiftsToDecrement) {
            System.debug('>>> Before decrement: ' + s.Assigned_User__c + ' count=' + s.Current_Lead_Count__c);
            if (s.Current_Lead_Count__c != null && s.Current_Lead_Count__c > 0) {
                s.Current_Lead_Count__c -= 1;
            }
            System.debug('>>> After decrement: ' + s.Assigned_User__c + ' count=' + s.Current_Lead_Count__c);
        }

        if (!shiftsToDecrement.isEmpty()) update shiftsToDecrement;

        // Create SLA breach audit logs for each expired assignment
        List<SLA_Breach_Log__c> breachLogs = new List<SLA_Breach_Log__c>();
        for (Lead_Queue__c entry : expiredEntries) {
            breachLogs.add(new SLA_Breach_Log__c(
                Rep_User__c    = entry.Assigned_To__c,
                Lead__c        = entry.Lead__c,
                Lead_Queue__c  = entry.Id,
                Assigned_At__c = entry.Assigned_At__c,
                Expired_At__c  = now
            ));
        }
        if (!breachLogs.isEmpty()) insert breachLogs;

        for (Lead_Queue__c entry : expiredEntries) {
            String leadName = entry.Name != null
                ? entry.Name.substringAfterLast('| ') : 'Unknown';
            entry.Status__c           = 'Waiting';
            entry.Assigned_To__c      = null;
            entry.Assigned_At__c      = null;
            entry.SLA_Deadline__c     = null;
            entry.Queue_Entry_Time__c = DateTime.now();
            entry.Name                = 'LQ | Waiting | ' + leadName;
        }

        update expiredEntries;

        expiredAlreadyRan = false;

        // Optional diagnostics to understand capacity after decrement
        List<Shift__c> availableAfterDecrement = ShiftSelector.getActiveShifts();
        System.debug('>>> Active shift count: ' + availableAfterDecrement.size());
        for (Shift__c s : availableAfterDecrement) {
            System.debug('>>> Available: ' + s.Id + ' count=' + s.Current_Lead_Count__c);
        }

        List<Lead_Queue__c> allWaiting = [
            SELECT Id, Lead__c, Priority__c, Queue_Entry_Time__c, Status__c
            FROM Lead_Queue__c
            WHERE Status__c = 'Waiting'
            ORDER BY Queue_Entry_Time__c ASC NULLS LAST
        ];

        System.debug('>>> Waiting entries count: ' + allWaiting.size());

        if (!allWaiting.isEmpty()) {
            processWaitingEntriesExcluding(allWaiting, expiredUserIds);
        }
    }

    /**
     * Adjusts shift load when assigned Lead_Queue__c records are deleted.
     * This ensures Current_Lead_Count__c does not drift when records are removed.
     *
     * @param deletedEntries Lead_Queue__c records being deleted.
     */
    /**
     * Adjusts shift counters when assigned queue records are deleted to prevent drift.
     */
    public static void processDeletedEntries(List<Lead_Queue__c> deletedEntries) {
        if (deletedEntries == null || deletedEntries.isEmpty()) return;

        Map<Id, Integer> deleteCountByUser = new Map<Id, Integer>();
        for (Lead_Queue__c entry : deletedEntries) {
            if (entry.Assigned_To__c != null && entry.Status__c == 'Assigned') {
                Integer count = deleteCountByUser.get(entry.Assigned_To__c);
                deleteCountByUser.put(entry.Assigned_To__c, count == null ? 1 : count + 1);
            }
        }

        if (deleteCountByUser.isEmpty()) return;

        // Pull active shifts for affected users and subtract the number of deleted assigned entries
        List<Shift__c> shifts = [
            SELECT Id, Current_Lead_Count__c, Assigned_User__c
            FROM Shift__c
            WHERE Assigned_User__c IN :deleteCountByUser.keySet()
            AND Is_Active__c = true
        ];

        for (Shift__c s : shifts) {
            Integer deleteCount = deleteCountByUser.get(s.Assigned_User__c);
            if (s.Current_Lead_Count__c != null && deleteCount != null) {
                s.Current_Lead_Count__c = Math.max(0, s.Current_Lead_Count__c - deleteCount);
            }
        }

        if (!shifts.isEmpty()) update shifts;
    }

    /**
     * Assigns "Waiting" entries but excludes specific reps from consideration
     * (e.g., the ones who just breached SLA), to improve fairness.
     *
     * @param newEntries      Waiting queue entries to assign.
     * @param excludedUserIds Users to skip while selecting shifts.
     */
    /**
     * Assigns Waiting entries using round-robin but excludes specified reps (e.g., just breached SLA).
     * Falls back to all active shifts if exclusion removes all options.
     */
    public static void processWaitingEntriesExcluding(
        List<Lead_Queue__c> newEntries, Set<Id> excludedUserIds) {

        if (newEntries == null || newEntries.isEmpty()) return;

        // Build an available shift pool omitting excluded users first
        List<Shift__c> availableShifts = new List<Shift__c>();
        for (Shift__c s : ShiftSelector.getActiveShifts()) {
            if (!excludedUserIds.contains(s.Assigned_User__c)) {
                availableShifts.add(s);
            }
        }

        // If exclusion eliminates all options, fall back to all active shifts
        if (availableShifts.isEmpty()) {
            availableShifts = ShiftSelector.getActiveShifts();
        }

        if (availableShifts.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Lead_Queue__c lq : newEntries) {
            if (lq.Lead__c != null) leadIds.add(lq.Lead__c);
        }

        // Preload lead names once for display building
        Map<Id, Lead> leadMap = new Map<Id, Lead>([
            SELECT Id, FirstName, LastName FROM Lead WHERE Id IN :leadIds
        ]);

        Set<Id> userIds = new Set<Id>();
        for (Shift__c s : availableShifts) userIds.add(s.Assigned_User__c);
        Map<Id, String> userNameMap = new Map<Id, String>();
        // Cache assignee names
        for (User u : [SELECT Id, Name FROM User WHERE Id IN :userIds]) {
            userNameMap.put(u.Id, u.Name);
        }

        List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
        List<Lead> leadsToUpdate = new List<Lead>();

        for (Lead_Queue__c lq : newEntries) {
            if (availableShifts.isEmpty()) break;
            if (lq.Status__c != 'Waiting') continue;

            // Choose next shift via round-robin (exclusion already applied to pool)
            Shift__c selectedShift = RoundRobinService.getNextShift(availableShifts);
            if (selectedShift == null) break;

            Lead lead = leadMap.get(lq.Lead__c);
            String leadFullName = lead != null
                ? ((lead.FirstName != null ? lead.FirstName + ' ' : '')
                    + (lead.LastName != null ? lead.LastName : 'Unknown'))
                : 'Unknown';

            String assigneeName = userNameMap.get(selectedShift.Assigned_User__c);

            toUpdate.add(new Lead_Queue__c(
                Id              = lq.Id,
                Name            = 'LQ | ' + assigneeName + ' | ' + leadFullName,
                Status__c       = 'Assigned',
                Assigned_To__c  = selectedShift.Assigned_User__c,
                Assigned_At__c  = DateTime.now(),
                SLA_Deadline__c = DateTime.now().addMinutes(5)
            ));

            leadsToUpdate.add(new Lead(
                Id      = lq.Lead__c,
                OwnerId = selectedShift.Assigned_User__c
            ));

            // Update in-memory load and the central counter service
            selectedShift.Current_Lead_Count__c =
                (selectedShift.Current_Lead_Count__c != null
                ? selectedShift.Current_Lead_Count__c : 0) + 1;

            RoundRobinService.incrementLeadCount(selectedShift.Id);

            // Stop using a shift once it reaches capacity in this transaction
            if (selectedShift.Current_Lead_Count__c >= selectedShift.Max_Capacity__c) {
                availableShifts.remove(availableShifts.indexOf(selectedShift));
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!leadsToUpdate.isEmpty()) update leadsToUpdate;
    }
}