/**
 * LeadShiftDashboardControllerTest
 * --------------------------------
 * Coverage-focused unit tests for LeadShiftDashboardController — the @AuraEnabled
 * backend for the Lead Shift dashboard LWC.
 *
 * Methods exercised (all inside Test.startTest/stopTest, empty + populated paths):
 *   - getShiftOverview(Long)   -> List<ShiftInfo>
 *   - getSummary(Long)         -> DashboardSummary
 *   - getRecentActivities(Long)-> List<ActivityEntry>
 *
 * Governor / DML discipline (see CLAUDE.md gotchas):
 *   - Users are created inside System.runAs(...) to dodge MIXED_DML_OPERATION.
 *   - Leads are inserted in BULK with the LeadShiftTriggerHandler bypassed, so the
 *     shift-intake path never runs SOQL-per-record ("Too many SOQL queries: 101").
 *   - Shifts are deactivated before seeding Waiting Lead_Queue__c rows so the raw
 *     LeadQueueTrigger doesn't auto-assign them, then reactivated as needed.
 *   - Reseller__c.Tier__c is a read-only formula and is never touched.
 */
@isTest
private class LeadShiftDashboardControllerTest {

    // ---------------------------------------------------------------------
    // Shared data: 2 reps + 4 active/inactive shifts covering the branches
    // of getShiftOverview (null user, null counts, zero capacity, inactive).
    // No Lead_Queue__c is seeded here — each test controls its own queue data.
    // ---------------------------------------------------------------------
    @TestSetup
    static void makeData() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];

        List<User> reps = new List<User>();
        Long stamp = DateTime.now().getTime();
        for (Integer i = 0; i < 2; i++) {
            reps.add(new User(
                FirstName        = 'Dash',
                LastName         = 'Rep' + i,
                Alias            = 'dr' + i,
                Email            = 'dashrep' + i + '@urlatest.example.com',
                Username         = 'dashrep' + i + '.' + stamp + '@urlatest.example.com',
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

        // Shift 0: fully populated, has capacity, positive-hour window (always "on shift").
        shifts.add(new Shift__c(
            Assigned_User__c      = reps[0].Id,
            Timezone__c           = 'America/New_York',
            Start_Hour__c         = 0,
            End_Hour__c           = 24,
            Is_Active__c          = true,
            Current_Lead_Count__c = 2,
            Max_Capacity__c       = 5
        ));
        // Shift 1: null count + null capacity -> exercises the null-coalesce branches.
        shifts.add(new Shift__c(
            Assigned_User__c      = reps[1].Id,
            Timezone__c           = 'Europe/Berlin',
            Start_Hour__c         = 0,
            End_Hour__c           = 24,
            Is_Active__c          = true,
            Current_Lead_Count__c = null,
            Max_Capacity__c       = null
        ));
        // Shift 2: no assignee + zero capacity -> null-user branch + capacityPercent else-branch.
        shifts.add(new Shift__c(
            Assigned_User__c      = null,
            Timezone__c           = 'America/New_York',
            Start_Hour__c         = 0,
            End_Hour__c           = 24,
            Is_Active__c          = true,
            Current_Lead_Count__c = 0,
            Max_Capacity__c       = 0
        ));
        // Shift 3: inactive -> excluded from the active-shift query.
        shifts.add(new Shift__c(
            Assigned_User__c      = reps[0].Id,
            Timezone__c           = 'America/New_York',
            Start_Hour__c         = 0,
            End_Hour__c           = 24,
            Is_Active__c          = false,
            Current_Lead_Count__c = 1,
            Max_Capacity__c       = 3
        ));
        insert shifts;
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    /** Bulk-insert leads WITHOUT firing the shift-intake handler. */
    private static List<Lead> seedLeads(Integer n) {
        TriggerHandler.bypass('LeadShiftTriggerHandler');
        List<Lead> leads = new List<Lead>();
        for (Integer i = 0; i < n; i++) {
            leads.add(new Lead(
                FirstName = 'Q',
                LastName  = 'Lead' + i,
                Company   = 'Test Co',
                Status    = 'Open - Not Contacted'
            ));
        }
        insert leads;   // single bulk DML -> one trigger invocation
        TriggerHandler.clearBypass('LeadShiftTriggerHandler');
        return leads;
    }

    private static Id firstRepId() {
        return [SELECT Assigned_User__c FROM Shift__c WHERE Max_Capacity__c = 5 LIMIT 1].Assigned_User__c;
    }

    private static void setAllShiftsActive(Boolean active) {
        List<Shift__c> all = [SELECT Id, Is_Active__c FROM Shift__c];
        for (Shift__c s : all) s.Is_Active__c = active;
        update all;
    }

    // ---------------------------------------------------------------------
    // 1. getShiftOverview — populated: returns one ShiftInfo per ACTIVE shift,
    //    with completed-count aggregation, capacity %, on-shift flag, tz math.
    // ---------------------------------------------------------------------
    @isTest
    static void getShiftOverview_populated_returnsActiveShiftInfos() {
        Id repId = firstRepId();

        // Two Completed queue entries for rep0 -> completedCount aggregation.
        List<Lead> leads = seedLeads(2);
        List<Lead_Queue__c> completed = new List<Lead_Queue__c>();
        for (Integer i = 0; i < leads.size(); i++) {
            completed.add(new Lead_Queue__c(
                Name                = 'LQ Done ' + i,
                Lead__c             = leads[i].Id,
                Status__c           = 'Completed',
                Assigned_To__c      = repId,
                Queue_Entry_Time__c = DateTime.now().addMinutes(-30),
                Priority__c         = 1
            ));
        }
        insert completed;   // Completed rows are skipped by the waiting-processor

        Test.startTest();
        List<LeadShiftDashboardController.ShiftInfo> infos =
            LeadShiftDashboardController.getShiftOverview(1L);
        Test.stopTest();

        System.assertNotEquals(null, infos, 'Overview should never be null');
        System.assertEquals(3, infos.size(), '3 of the 4 shifts are active');

        // Inspect the fully-populated rep0 shift (Max_Capacity 5, count 2 -> 40%).
        Boolean sawRepShift = false;
        Boolean sawNullUserShift = false;
        for (LeadShiftDashboardController.ShiftInfo info : infos) {
            System.assertNotEquals(null, info.shiftId, 'shiftId set');
            System.assertNotEquals(null, info.timezone, 'timezone set');
            System.assertNotEquals(null, info.localTime, 'localTime formatted');
            System.assertNotEquals(null, info.isOnShift, 'isOnShift computed');

            if (info.assigneeName == null) {
                sawNullUserShift = true;
                System.assertEquals(0, info.capacityPercent,
                    'Zero-capacity shift -> 0% capacity');
            }
            if (info.maxCapacity == 5) {
                sawRepShift = true;
                System.assertEquals(2, info.currentLeadCount, 'currentLeadCount from field');
                System.assertEquals(40, info.capacityPercent, '2 of 5 -> 40%');
                System.assertEquals(true, info.isOnShift, '0..24 window is always on shift');
                System.assertEquals(2, info.completedCount, 'Two completed leads for this rep');
            }
        }
        System.assertEquals(true, sawRepShift, 'Populated rep shift present');
        System.assertEquals(true, sawNullUserShift, 'Null-user / zero-capacity shift present');
    }

    // ---------------------------------------------------------------------
    // 2. getShiftOverview — empty: no active shifts -> empty list.
    // ---------------------------------------------------------------------
    @isTest
    static void getShiftOverview_noActiveShifts_returnsEmpty() {
        setAllShiftsActive(false);

        Test.startTest();
        List<LeadShiftDashboardController.ShiftInfo> infos =
            LeadShiftDashboardController.getShiftOverview(2L);
        Test.stopTest();

        System.assertNotEquals(null, infos, 'Should return an empty list, not null');
        System.assertEquals(0, infos.size(), 'No active shifts -> empty overview');
    }

    // ---------------------------------------------------------------------
    // 3. getSummary — populated: waiting / assigned / completed tallies plus
    //    active-shift counting and Lagos clock fields.
    // ---------------------------------------------------------------------
    @isTest
    static void getSummary_populated_returnsTallies() {
        Id repId = firstRepId();

        // Seed Waiting entries while shifts are inactive so they stay Waiting.
        setAllShiftsActive(false);
        List<Lead> leads = seedLeads(6);

        List<Lead_Queue__c> rows = new List<Lead_Queue__c>();
        // 3 Waiting
        for (Integer i = 0; i < 3; i++) {
            rows.add(new Lead_Queue__c(
                Name = 'LQ Wait ' + i, Lead__c = leads[i].Id, Status__c = 'Waiting',
                Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        }
        // 1 Assigned to rep0
        rows.add(new Lead_Queue__c(
            Name = 'LQ Asg', Lead__c = leads[3].Id, Status__c = 'Assigned',
            Assigned_To__c = repId, Assigned_At__c = DateTime.now(),
            SLA_Deadline__c = DateTime.now().addMinutes(30),
            Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        // 2 Completed
        for (Integer i = 4; i < 6; i++) {
            rows.add(new Lead_Queue__c(
                Name = 'LQ Comp ' + i, Lead__c = leads[i].Id, Status__c = 'Completed',
                Assigned_To__c = repId, Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        }
        insert rows;

        // Reactivate shifts so activeShiftCount > 0 and rep0 is an active user.
        setAllShiftsActive(true);

        Test.startTest();
        LeadShiftDashboardController.DashboardSummary summary =
            LeadShiftDashboardController.getSummary(3L);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(3, summary.totalWaiting, 'Three Waiting entries');
        System.assertEquals(2, summary.totalCompleted, 'Two Completed entries');
        System.assertEquals(1, summary.totalAssigned, 'One Assigned entry for an active rep');
        System.assert(summary.activeShiftCount > 0, 'At least one active shift within its window');
        System.assertEquals(4, summary.totalShiftCount, 'All four shifts reactivated -> queried as active');
        System.assert(summary.lagosCurrentHour >= 0 && summary.lagosCurrentHour < 24, 'Lagos hour in range');
        System.assert(summary.lagosCurrentMinute >= 0 && summary.lagosCurrentMinute < 60, 'Lagos minute in range');
    }

    // ---------------------------------------------------------------------
    // 4. getSummary — empty: no queue data, no active shifts -> zeros.
    // ---------------------------------------------------------------------
    @isTest
    static void getSummary_empty_returnsZeros() {
        setAllShiftsActive(false);

        Test.startTest();
        LeadShiftDashboardController.DashboardSummary summary =
            LeadShiftDashboardController.getSummary(4L);
        Test.stopTest();

        System.assertNotEquals(null, summary, 'Summary should not be null');
        System.assertEquals(0, summary.totalWaiting, 'No waiting leads');
        System.assertEquals(0, summary.totalCompleted, 'No completed leads');
        System.assertEquals(0, summary.totalAssigned, 'No active users -> zero assigned');
        System.assertEquals(0, summary.activeShiftCount, 'No active shifts');
        System.assertEquals(0, summary.totalShiftCount, 'No active shifts queried');
    }

    // ---------------------------------------------------------------------
    // 5. getRecentActivities — populated: covers the "assigned to" and
    //    "is waiting" NewLead message branches, the Completed branch with an
    //    Unknown rep, and the >15 trim path.
    // ---------------------------------------------------------------------
    @isTest
    static void getRecentActivities_populated_returnsTrimmedFeed() {
        Id repId = firstRepId();

        // Keep shifts inactive so Waiting rows are not auto-assigned on insert.
        setAllShiftsActive(false);
        List<Lead> leads = seedLeads(17);

        List<Lead_Queue__c> rows = new List<Lead_Queue__c>();
        // 10 Waiting (no assignee) -> "is waiting" branch
        for (Integer i = 0; i < 10; i++) {
            rows.add(new Lead_Queue__c(
                Name = 'LQ W ' + i, Lead__c = leads[i].Id, Status__c = 'Waiting',
                Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        }
        // 1 Assigned (with rep) -> "assigned to" branch in the created loop
        rows.add(new Lead_Queue__c(
            Name = 'LQ A', Lead__c = leads[10].Id, Status__c = 'Assigned',
            Assigned_To__c = repId, Assigned_At__c = DateTime.now(),
            SLA_Deadline__c = DateTime.now().addMinutes(30),
            Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        // 6 Completed (no assignee) -> Completed loop with "Unknown" rep
        for (Integer i = 11; i < 17; i++) {
            rows.add(new Lead_Queue__c(
                Name = 'LQ C ' + i, Lead__c = leads[i].Id, Status__c = 'Completed',
                Queue_Entry_Time__c = DateTime.now(), Priority__c = 1));
        }
        insert rows;

        Test.startTest();
        List<LeadShiftDashboardController.ActivityEntry> feed =
            LeadShiftDashboardController.getRecentActivities(5L);
        Test.stopTest();

        System.assertNotEquals(null, feed, 'Feed should not be null');
        System.assertEquals(15, feed.size(), 'Feed is trimmed to 15 most-recent entries');
        for (LeadShiftDashboardController.ActivityEntry e : feed) {
            System.assertNotEquals(null, e.activityId, 'activityId set');
            System.assertNotEquals(null, e.eventType, 'eventType set');
            System.assertNotEquals(null, e.timestamp, 'timestamp set');
            System.assert(String.isNotBlank(e.message), 'message populated');
        }
    }

    // ---------------------------------------------------------------------
    // 6. getRecentActivities — empty: no recent queue rows -> empty feed.
    // ---------------------------------------------------------------------
    @isTest
    static void getRecentActivities_empty_returnsEmptyFeed() {
        Test.startTest();
        List<LeadShiftDashboardController.ActivityEntry> feed =
            LeadShiftDashboardController.getRecentActivities(6L);
        Test.stopTest();

        System.assertNotEquals(null, feed, 'Feed should not be null');
        System.assertEquals(0, feed.size(), 'No recent activity -> empty feed');
    }
}
