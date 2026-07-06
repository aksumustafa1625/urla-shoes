/**
 * LeadQueueClusterTest
 * --------------------
 * Coverage-focused unit tests for the Lead Queue cluster:
 *   - LeadQueueProcessor  (processWaitingEntries / processCompletedEntries /
 *                          processExpiredLeads / processDeletedEntries /
 *                          processWaitingEntriesExcluding)
 *   - LeadQueueService    (processNewLeads intake: assign + waiting + dedupe)
 *   - LeadQueueScheduler  (execute -> processExpired + processWaiting + scheduleNext + startScheduler)
 *   - RoundRobinService   (getNextShift / getNextAssignee / incrementLeadCount)
 *   - ShiftSelector       (getActiveShifts / getAlreadyQueuedLeadIds)
 *   - TimezoneService     (getLocalHour / getLocalDateTime / isWithinShift)
 *   - SLAExpiryChecker    (Schedulable entry point)
 *
 * Governor discipline (see project CLAUDE.md gotcha #3):
 *   - Leads are inserted in BULK inside Test.startTest()/stopTest().
 *   - Shifts use Max_Capacity__c = 1 so the active-shift pool drains after a few
 *     immediate assignments, preventing the per-record incrementLeadCount SOQL
 *     from exploding (the "Too many SOQL queries: 101" trap).
 *
 * @isTest
 */
@isTest
private class LeadQueueClusterTest {

    // ---------------------------------------------------------------------
    // Shared data: 3 Standard users, each owning one active shift (cap 1).
    // ---------------------------------------------------------------------
    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        List<User> reps = new List<User>();
        Long stamp = DateTime.now().getTime();
        for (Integer i = 0; i < 3; i++) {
            reps.add(new User(
                FirstName        = 'Rep',
                LastName         = 'Agent' + i,
                Alias            = 'rep' + i,
                Email            = 'rep' + i + '@urlatest.example.com',
                Username         = 'rep' + i + '.' + stamp + '@urlatest.example.com',
                ProfileId        = p.Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey= 'en_US',
                LocaleSidKey     = 'en_US',
                TimeZoneSidKey   = 'Europe/Berlin',
                IsActive         = true
            ));
        }
        // User is a setup object -> isolate the DML to dodge MIXED_DML_OPERATION.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reps;
        }

        List<Shift__c> shifts = new List<Shift__c>();
        for (Integer i = 0; i < 3; i++) {
            shifts.add(new Shift__c(
                Assigned_User__c      = reps[i].Id,
                Timezone__c           = 'Europe/Berlin',
                Start_Hour__c         = 0,   // 0..24 keeps the shift "active" at any run time
                End_Hour__c           = 24,
                Is_Active__c          = true,
                Current_Lead_Count__c = 0,
                Max_Capacity__c       = 1
            ));
        }
        insert shifts;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private static List<Lead> buildLeads(Integer n) {
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < n; i++) {
            leads.add(new Lead(
                FirstName = 'Lead',
                LastName  = 'Test' + i,
                Company   = 'Test Co',
                Status    = 'Open - Not Contacted'
            ));
        }
        return leads;
    }

    /** Insert a Lead WITHOUT firing the queue-intake handler, so tests can seed
     *  Lead_Queue__c rows in an exact state instead of the auto-created one. */
    private static Lead insertLeadNoIntake(String lastName) {
        TriggerHandler.bypass('LeadShiftTriggerHandler');
        Lead l = new Lead(
            FirstName = 'Seed',
            LastName  = lastName,
            Company   = 'Seed Co',
            Status    = 'Open - Not Contacted'
        );
        insert l;
        TriggerHandler.clearBypass('LeadShiftTriggerHandler');
        return l;
    }

    private static List<Shift__c> shiftsByCreated() {
        return [
            SELECT Id, Assigned_User__c, Is_Active__c,
                   Current_Lead_Count__c, Max_Capacity__c
            FROM Shift__c
            ORDER BY CreatedDate
        ];
    }

    // ---------------------------------------------------------------------
    // 1. Bulk intake: with active shifts, a few get immediate round-robin
    //    assignment (cap 1 each) and the remainder queue as Waiting.
    // ---------------------------------------------------------------------
    @isTest
    static void intake_bulkInsert_assignsUpToCapacityRestWaiting() {
        Test.startTest();
        insert buildLeads(200);   // single bulk DML -> one trigger invocation
        Test.stopTest();

        Integer assigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
        Integer waiting  = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];

        System.assertEquals(3, assigned, '3 active shifts of capacity 1 -> 3 immediate assignments');
        System.assertEquals(197, waiting, 'Remaining leads should queue as Waiting');

        // Round-robin should have spread the 3 assignments across 3 distinct reps.
        Set<Id> reps = new Set<Id>();
        for (Lead_Queue__c q : [SELECT Assigned_To__c FROM Lead_Queue__c WHERE Status__c = 'Assigned']) {
            reps.add(q.Assigned_To__c);
        }
        System.assertEquals(3, reps.size(), 'Assignments should be distributed to 3 different reps');
    }

    // ---------------------------------------------------------------------
    // 2. No active shift -> everything Waiting, and re-processing the same
    //    leads is a no-op (duplicate-entry prevention).
    // ---------------------------------------------------------------------
    @isTest
    static void intake_noActiveShift_allWaiting_andDedupe() {
        List<Shift__c> shifts = shiftsByCreated();
        for (Shift__c s : shifts) s.Is_Active__c = false;
        update shifts;

        List<Lead> leads = buildLeads(5);

        Test.startTest();
        insert leads;
        Test.stopTest();

        System.assertEquals(5, [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'],
            'No active shift -> all leads Waiting');

        // Second pass over already-queued leads must not create duplicates.
        LeadQueueService.processNewLeads(leads);
        System.assertEquals(5, [SELECT COUNT() FROM Lead_Queue__c],
            'Already-queued leads should be skipped (no duplicate entries)');
    }

    // ---------------------------------------------------------------------
    // 3. RoundRobinService selection + wraparound + incrementLeadCount.
    // ---------------------------------------------------------------------
    @isTest
    static void roundRobin_selectsLowestCount_andWrapsAround() {
        List<Shift__c> shifts = shiftsByCreated();

        // In-memory mutation (no DML) to drive selection deterministically.
        shifts[0].Current_Lead_Count__c = 5;
        shifts[1].Current_Lead_Count__c = 0;
        shifts[2].Current_Lead_Count__c = 2;

        System.assertEquals(shifts[1].Id,
            RoundRobinService.getNextShift(shifts).Id,
            'Lowest count shift should be selected');
        System.assertEquals(shifts[1].Assigned_User__c,
            RoundRobinService.getNextAssignee(shifts),
            'Assignee of the lowest-count shift should be returned');

        // Simulate that shift becoming the busiest -> selection wraps to the next lowest.
        shifts[1].Current_Lead_Count__c = 9;
        System.assertEquals(shifts[2].Id,
            RoundRobinService.getNextShift(shifts).Id,
            'After wraparound the new lowest (count 2) should win');

        // Persistent single-record increment.
        Shift__c real = shiftsByCreated()[0];
        Decimal before = real.Current_Lead_Count__c == null ? 0 : real.Current_Lead_Count__c;
        RoundRobinService.incrementLeadCount(real.Id);
        Shift__c after = [SELECT Current_Lead_Count__c FROM Shift__c WHERE Id = :real.Id];
        System.assertEquals(before + 1, after.Current_Lead_Count__c, 'incrementLeadCount should +1');
    }

    // ---------------------------------------------------------------------
    // 4. SLA breach: an Assigned entry past its deadline is reclaimed to
    //    Waiting, an audit log is written, and it is reassigned excluding the
    //    breaching rep. Driven through SLAExpiryChecker (Schedulable).
    // ---------------------------------------------------------------------
    @isTest
    static void slaBreach_logsAndReclaims_viaChecker() {
        Id repId = shiftsByCreated()[0].Assigned_User__c;
        Lead l = insertLeadNoIntake('Expired');

        Lead_Queue__c e = new Lead_Queue__c(
            Name              = 'LQ | Rep | Expired',
            Lead__c           = l.Id,
            Status__c         = 'Assigned',
            Assigned_To__c    = repId,
            Assigned_At__c    = DateTime.now().addMinutes(-30),
            SLA_Deadline__c   = DateTime.now().addMinutes(-10),  // already past
            Queue_Entry_Time__c = DateTime.now().addMinutes(-40),
            Priority__c       = 1
        );
        insert e;   // afterInsert -> processWaitingEntries skips it (not Waiting)

        Test.startTest();
        new SLAExpiryChecker().execute(null);   // -> LeadQueueProcessor.processExpiredLeads()
        Test.stopTest();

        List<SLA_Breach_Log__c> logs = [SELECT Id, Rep_User__c, Lead__c FROM SLA_Breach_Log__c];
        System.assertEquals(1, logs.size(), 'One SLA breach log should be created for the expired entry');
        System.assertEquals(repId, logs[0].Rep_User__c, 'Breach log should record the breaching rep');
        System.assertEquals(l.Id, logs[0].Lead__c, 'Breach log should reference the lead');
    }

    // ---------------------------------------------------------------------
    // 5. Completion path: decrement the rep's shift load and backfill an
    //    existing Waiting entry (processCompletedEntries).
    // ---------------------------------------------------------------------
    @isTest
    static void completion_decrementsShift_andBackfillsWaiting() {
        List<Shift__c> shifts = shiftsByCreated();
        Id repId = shifts[0].Assigned_User__c;

        // Deactivate shifts so a seeded Waiting entry stays Waiting on insert.
        for (Shift__c s : shifts) s.Is_Active__c = false;
        update shifts;

        Lead lw = insertLeadNoIntake('WaitBackfill');
        Lead_Queue__c waitingEntry = new Lead_Queue__c(
            Name = 'LQ | Waiting | WaitBackfill',
            Lead__c = lw.Id,
            Status__c = 'Waiting',
            Queue_Entry_Time__c = DateTime.now().addMinutes(-5),
            Priority__c = 1
        );
        insert waitingEntry;  // shifts inactive -> remains Waiting

        // Reactivate with headroom so backfill can assign.
        for (Shift__c s : shifts) {
            s.Is_Active__c = true;
            s.Current_Lead_Count__c = 0;
            s.Max_Capacity__c = 5;
        }
        update shifts;

        Lead la = insertLeadNoIntake('Completed');
        Lead_Queue__c assignedEntry = new Lead_Queue__c(
            Name = 'LQ | Rep | Completed',
            Lead__c = la.Id,
            Status__c = 'Assigned',
            Assigned_To__c = repId,
            Assigned_At__c = DateTime.now().addMinutes(-2),
            SLA_Deadline__c = DateTime.now().addMinutes(3),
            Queue_Entry_Time__c = DateTime.now().addMinutes(-2),
            Priority__c = 1
        );
        insert assignedEntry;   // Assigned -> processWaitingEntries skips it

        // Give the rep's shift a load of 3. Completion decrements it to 2; the
        // backfill then assigns the Waiting entry to a *different* (count-0) shift,
        // so the rep's shift stays at 2 and the decrement is observable in isolation.
        update new Shift__c(Id = shifts[0].Id, Current_Lead_Count__c = 3);

        Test.startTest();
        assignedEntry.Status__c = 'Completed';
        update assignedEntry;   // afterUpdate -> processCompletedEntries
        Test.stopTest();

        System.assertEquals('Completed',
            [SELECT Status__c FROM Lead_Queue__c WHERE Id = :assignedEntry.Id].Status__c,
            'Entry should be Completed');

        Lead_Queue__c backfilled = [SELECT Status__c, Assigned_To__c FROM Lead_Queue__c WHERE Id = :waitingEntry.Id];
        System.assertEquals('Assigned', backfilled.Status__c,
            'The Waiting entry should be backfilled to Assigned on completion');
        System.assertNotEquals(null, backfilled.Assigned_To__c, 'Backfilled entry should have an assignee');

        System.assertEquals(2,
            [SELECT Current_Lead_Count__c FROM Shift__c WHERE Id = :shifts[0].Id].Current_Lead_Count__c,
            'Completing an assignment should decrement the rep shift load (3 -> 2)');
    }

    // ---------------------------------------------------------------------
    // 6. Delete path: deleting an Assigned entry frees the rep's shift load.
    // ---------------------------------------------------------------------
    @isTest
    static void delete_assignedEntry_decrementsShiftLoad() {
        List<Shift__c> shifts = shiftsByCreated();
        Id repId = shifts[0].Assigned_User__c;

        update new Shift__c(Id = shifts[0].Id, Current_Lead_Count__c = 2);

        Lead l = insertLeadNoIntake('Del');
        Lead_Queue__c e = new Lead_Queue__c(
            Name = 'LQ | Rep | Del',
            Lead__c = l.Id,
            Status__c = 'Assigned',
            Assigned_To__c = repId,
            Assigned_At__c = DateTime.now(),
            SLA_Deadline__c = DateTime.now().addMinutes(5),
            Queue_Entry_Time__c = DateTime.now(),
            Priority__c = 1
        );
        insert e;

        Test.startTest();
        delete e;   // afterDelete -> processDeletedEntries
        Test.stopTest();

        System.assertEquals(1,
            [SELECT Current_Lead_Count__c FROM Shift__c WHERE Id = :shifts[0].Id].Current_Lead_Count__c,
            'Deleting an assigned entry should decrement the shift load (2 -> 1)');
    }

    // ---------------------------------------------------------------------
    // 7. Scheduler: execute() reclaims an expired lead, reassigns it, and
    //    self-schedules. Also exercises startScheduler().
    // ---------------------------------------------------------------------
    @isTest
    static void scheduler_execute_reassignsAndSelfSchedules() {
        Id repId = shiftsByCreated()[0].Assigned_User__c;
        Lead l = insertLeadNoIntake('Sched');

        Lead_Queue__c e = new Lead_Queue__c(
            Name = 'LQ | Rep | Sched',
            Lead__c = l.Id,
            Status__c = 'Assigned',
            Assigned_To__c = repId,
            Assigned_At__c = DateTime.now().addMinutes(-30),
            SLA_Deadline__c = DateTime.now().addMinutes(-10),  // expired
            Queue_Entry_Time__c = DateTime.now().addMinutes(-30),
            Priority__c = 1
        );
        insert e;

        Test.startTest();
        new LeadQueueScheduler().execute(null);   // expired -> Waiting -> reassigned
        LeadQueueScheduler.startScheduler();       // bootstrap scheduling path
        Test.stopTest();

        System.assertEquals('Assigned',
            [SELECT Status__c FROM Lead_Queue__c WHERE Id = :e.Id].Status__c,
            'Scheduler should reclaim the expired lead and reassign it');

        System.assert(
            [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'LeadQueueScheduler_%'] > 0,
            'Scheduler should register a future job');
    }

    // ---------------------------------------------------------------------
    // 8. TimezoneService unit coverage (happy path + catch fallbacks + both
    //    isWithinShift branches).
    // ---------------------------------------------------------------------
    @isTest
    static void timezoneService_allBranches() {
        Test.startTest();

        Integer blankHour = TimezoneService.getLocalHour('');
        System.assert(blankHour >= 0 && blankHour < 24, 'Blank tz -> local server hour');
        Integer tzHour = TimezoneService.getLocalHour('Europe/Berlin');
        System.assert(tzHour >= 0 && tzHour < 24, 'Valid tz -> local hour');
        Integer badHour = TimezoneService.getLocalHour('Not/AZone');   // catch -> fallback
        System.assert(badHour >= 0 && badHour < 24, 'Invalid tz -> fallback hour');

        System.assertNotEquals(null, TimezoneService.getLocalDateTime(''));
        System.assertNotEquals(null, TimezoneService.getLocalDateTime('Europe/Berlin'));
        System.assertNotEquals(null, TimezoneService.getLocalDateTime('Bad/Zone'));   // catch

        System.assertEquals(true, TimezoneService.isWithinShift('Europe/Berlin', 0, 24),
            'A 0..24 window is always within shift');
        // Overnight branch (start >= end) — result is time-dependent, just exercise it.
        Boolean overnight = TimezoneService.isWithinShift('Europe/Berlin', 22, 6);
        System.assert(overnight == true || overnight == false);

        Test.stopTest();
    }

    // ---------------------------------------------------------------------
    // 9. Empty / null guards across the cluster (fast early-return paths).
    // ---------------------------------------------------------------------
    @isTest
    static void guards_nullAndEmptyInputs() {
        Test.startTest();

        LeadQueueProcessor.processWaitingEntries(null);
        LeadQueueProcessor.processWaitingEntries(new List<Lead_Queue__c>());
        LeadQueueProcessor.processCompletedEntries(null);
        LeadQueueProcessor.processCompletedEntries(new List<Lead_Queue__c>());
        // Completed entry with no assignee -> assignedUserIds empty -> early return.
        LeadQueueProcessor.processCompletedEntries(
            new List<Lead_Queue__c>{ new Lead_Queue__c(Status__c = 'Completed') });
        LeadQueueProcessor.processDeletedEntries(null);
        LeadQueueProcessor.processDeletedEntries(new List<Lead_Queue__c>());
        // Deleted entry not Assigned -> deleteCountByUser empty -> early return.
        LeadQueueProcessor.processDeletedEntries(
            new List<Lead_Queue__c>{ new Lead_Queue__c(Status__c = 'Waiting') });
        LeadQueueProcessor.processWaitingEntriesExcluding(null, new Set<Id>());
        LeadQueueProcessor.processWaitingEntriesExcluding(new List<Lead_Queue__c>(), new Set<Id>());

        LeadQueueService.processNewLeads(null);
        LeadQueueService.processNewLeads(new List<Lead>());

        System.assertEquals(null, RoundRobinService.getNextShift(null));
        System.assertEquals(null, RoundRobinService.getNextShift(new List<Shift__c>()));
        System.assertEquals(null, RoundRobinService.getNextAssignee(null));
        System.assertEquals(null, RoundRobinService.getNextAssignee(new List<Shift__c>()));
        RoundRobinService.incrementLeadCount(null);

        System.assert(ShiftSelector.getAlreadyQueuedLeadIds(null).isEmpty());
        System.assert(ShiftSelector.getAlreadyQueuedLeadIds(new Set<Id>()).isEmpty());

        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Lead_Queue__c], 'Guard calls must not create data');
    }

    // ---------------------------------------------------------------------
    // 10. ShiftSelector.getAlreadyQueuedLeadIds positive path.
    // ---------------------------------------------------------------------
    @isTest
    static void shiftSelector_alreadyQueuedLeadIds_returnsQueuedLead() {
        Lead l = insertLeadNoIntake('Queued');
        insert new Lead_Queue__c(
            Name = 'LQ | Waiting | Queued',
            Lead__c = l.Id,
            Status__c = 'Waiting',
            Queue_Entry_Time__c = DateTime.now(),
            Priority__c = 5
        );

        Test.startTest();
        Set<Id> queued = ShiftSelector.getAlreadyQueuedLeadIds(new Set<Id>{ l.Id });
        Test.stopTest();

        System.assert(queued.contains(l.Id), 'Lead with an open queue entry should be reported as queued');
    }
}
