public with sharing class LeadShiftDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<ShiftInfo> getShiftOverview(Long refreshToken) {
        List<Shift__c> shifts = [
            SELECT Id, Name, Assigned_User__c, Assigned_User__r.Name,
                   Timezone__c, Start_Hour__c, End_Hour__c,
                   Current_Lead_Count__c, Max_Capacity__c, Is_Active__c
            FROM Shift__c
            WHERE Is_Active__c = true
            ORDER BY Start_Hour__c ASC
        ];

        // Completed lead counts per user
        Set<Id> userIds = new Set<Id>();
        for (Shift__c s : shifts) {
            if (s.Assigned_User__c != null) userIds.add(s.Assigned_User__c);
        }

        Map<Id, Integer> completedByUser = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Assigned_To__c userId, COUNT(Id) cnt
            FROM Lead_Queue__c
            WHERE Assigned_To__c IN :userIds
            AND Status__c = 'Completed'
            GROUP BY Assigned_To__c
        ]) {
            completedByUser.put((Id)ar.get('userId'), (Integer)ar.get('cnt'));
        }

        List<ShiftInfo> result = new List<ShiftInfo>();

        for (Shift__c s : shifts) {
            ShiftInfo info = new ShiftInfo();
            info.shiftId = s.Id;
            info.shiftName = s.Name;
            info.assigneeName = s.Assigned_User__r.Name;
            info.timezone = s.Timezone__c;
            info.startHour = Integer.valueOf(s.Start_Hour__c);
            info.endHour = Integer.valueOf(s.End_Hour__c);
            info.currentLeadCount = s.Current_Lead_Count__c != null ? Integer.valueOf(s.Current_Lead_Count__c) : 0;
            info.maxCapacity = s.Max_Capacity__c != null ? Integer.valueOf(s.Max_Capacity__c) : 1;

            String localNow = DateTime.now().format('HH:mm', s.Timezone__c);
            info.localTime = localNow;

            Integer localHour = Integer.valueOf(DateTime.now().format('H', s.Timezone__c));
            info.isOnShift = isWithinShift(localHour, info.startHour, info.endHour);

            info.capacityPercent = info.maxCapacity > 0
                ? Math.round((Decimal.valueOf(info.currentLeadCount) / Decimal.valueOf(info.maxCapacity)) * 100)
                : 0;

            info.completedCount = completedByUser.containsKey(s.Assigned_User__c)
                ? completedByUser.get(s.Assigned_User__c) : 0;

            // Lagos-time equivalent for timeline visualization
            Integer lagosStart = Integer.valueOf(DateTime.newInstance(
                Date.today(), Time.newInstance(info.startHour, 0, 0, 0)
            ).format('H', s.Timezone__c));
            // Build an absolute UTC timestamp from local hours and reformat to Lagos
            DateTime utcStart = DateTime.newInstanceGmt(Date.today(), Time.newInstance(info.startHour, 0, 0, 0));
            DateTime utcEnd = DateTime.newInstanceGmt(Date.today(), Time.newInstance(info.endHour, 0, 0, 0));
            // Compute timezone offsets
            Integer tzOffset = Integer.valueOf(DateTime.now().format('Z', s.Timezone__c).substring(0, 3));
            Integer lagosOffset = Integer.valueOf(DateTime.now().format('Z', 'Africa/Lagos').substring(0, 3));
            info.lagosStartHour = Math.mod((info.startHour - tzOffset + lagosOffset + 48), 24);
            info.lagosEndHour = Math.mod((info.endHour - tzOffset + lagosOffset + 48), 24);

            result.add(info);
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardSummary getSummary(Long refreshToken) {
        DashboardSummary summary = new DashboardSummary();

        summary.totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
        summary.totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];

        Integer activeCount = 0;
        Set<Id> activeUserIds = new Set<Id>();
        List<Shift__c> shifts = [
            SELECT Assigned_User__c, Timezone__c, Start_Hour__c, End_Hour__c
            FROM Shift__c
            WHERE Is_Active__c = true
        ];
        for (Shift__c s : shifts) {
            Integer localHour = Integer.valueOf(DateTime.now().format('H', s.Timezone__c));
            if (isWithinShift(localHour, Integer.valueOf(s.Start_Hour__c), Integer.valueOf(s.End_Hour__c))) {
                activeCount++;
                if (s.Assigned_User__c != null) activeUserIds.add(s.Assigned_User__c);
            }
        }
        summary.activeShiftCount = activeCount;
        summary.totalShiftCount = shifts.size();
        summary.totalAssigned = activeUserIds.isEmpty()
            ? 0
            : [
                SELECT COUNT()
                FROM Lead_Queue__c
                WHERE Status__c = 'Assigned'
                AND Assigned_To__c IN :activeUserIds
            ];

        summary.lagosCurrentHour = Integer.valueOf(DateTime.now().format('H', 'Africa/Lagos'));
        summary.lagosCurrentMinute = Integer.valueOf(DateTime.now().format('m', 'Africa/Lagos'));

        return summary;
    }

    @AuraEnabled(cacheable=true)
    public static List<ActivityEntry> getRecentActivities(Long refreshToken) {
        List<ActivityEntry> results = new List<ActivityEntry>();
        DateTime cutoff = DateTime.now().addHours(-1);

        // Recently created queue entries (new leads arriving)
        for (Lead_Queue__c lq : [
            SELECT Id, CreatedDate, Status__c, Lead__r.Name, Assigned_To__r.Name
            FROM Lead_Queue__c
            WHERE CreatedDate >= :cutoff
            ORDER BY CreatedDate DESC
            LIMIT 15
        ]) {
            ActivityEntry e = new ActivityEntry();
            e.activityId = lq.Id + '-created';
            e.eventType = 'NewLead';
            e.timestamp = lq.CreatedDate;
            e.repName = lq.Assigned_To__r != null ? lq.Assigned_To__r.Name : '';
            String leadName = lq.Lead__r != null ? lq.Lead__r.Name : 'Unknown';
            e.message = lq.Status__c == 'Assigned' && String.isNotBlank(e.repName)
                ? 'New lead ' + leadName + ' assigned to ' + e.repName
                : 'New lead ' + leadName + ' is waiting';
            results.add(e);
        }

        // Recently completed entries
        for (Lead_Queue__c lq : [
            SELECT Id, LastModifiedDate, Assigned_To__r.Name, Lead__r.Name
            FROM Lead_Queue__c
            WHERE Status__c = 'Completed'
            AND LastModifiedDate >= :cutoff
            ORDER BY LastModifiedDate DESC
            LIMIT 15
        ]) {
            ActivityEntry e = new ActivityEntry();
            e.activityId = lq.Id + '-completed';
            e.eventType = 'Completed';
            e.timestamp = lq.LastModifiedDate;
            e.repName = lq.Assigned_To__r != null ? lq.Assigned_To__r.Name : 'Unknown';
            String leadName = lq.Lead__r != null ? lq.Lead__r.Name : 'a lead';
            e.message = e.repName + ' completed ' + leadName;
            results.add(e);
        }

        // Sort combined list by timestamp desc, keep most recent
        results.sort(new ActivityComparator());
        if (results.size() > 15) {
            List<ActivityEntry> trimmed = new List<ActivityEntry>();
            for (Integer i = 0; i < 15; i++) trimmed.add(results[i]);
            return trimmed;
        }
        return results;
    }

    private static Boolean isWithinShift(Integer localHour, Integer startHour, Integer endHour) {
        if (startHour < endHour) {
            return localHour >= startHour && localHour < endHour;
        }
        return localHour >= startHour || localHour < endHour;
    }

    public class ShiftInfo {
        @AuraEnabled public String shiftId;
        @AuraEnabled public String shiftName;
        @AuraEnabled public String assigneeName;
        @AuraEnabled public String timezone;
        @AuraEnabled public Integer startHour;
        @AuraEnabled public Integer endHour;
        @AuraEnabled public Integer currentLeadCount;
        @AuraEnabled public Integer maxCapacity;
        @AuraEnabled public String localTime;
        @AuraEnabled public Boolean isOnShift;
        @AuraEnabled public Long capacityPercent;
        @AuraEnabled public Integer completedCount;
        @AuraEnabled public Integer lagosStartHour;
        @AuraEnabled public Integer lagosEndHour;
    }

    public class DashboardSummary {
        @AuraEnabled public Integer totalWaiting;
        @AuraEnabled public Integer totalAssigned;
        @AuraEnabled public Integer totalCompleted;
        @AuraEnabled public Integer activeShiftCount;
        @AuraEnabled public Integer totalShiftCount;
        @AuraEnabled public Integer lagosCurrentHour;
        @AuraEnabled public Integer lagosCurrentMinute;
    }

    public class ActivityEntry {
        @AuraEnabled public String activityId;
        @AuraEnabled public String eventType;
        @AuraEnabled public DateTime timestamp;
        @AuraEnabled public String repName;
        @AuraEnabled public String message;
    }

    public class ActivityComparator implements Comparator<ActivityEntry> {
        public Integer compare(ActivityEntry a, ActivityEntry b) {
            if (a.timestamp == b.timestamp) return 0;
            return a.timestamp > b.timestamp ? -1 : 1;
        }
    }
}
