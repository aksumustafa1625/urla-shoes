public with sharing class LeadShiftDashboardController {

    @AuraEnabled(cacheable=true)
    public static List<ShiftInfo> getShiftOverview() {
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

            result.add(info);
        }

        return result;
    }

    @AuraEnabled(cacheable=true)
    public static DashboardSummary getSummary() {
        DashboardSummary summary = new DashboardSummary();

        summary.totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
        summary.totalAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
        summary.totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];

        Integer activeCount = 0;
        List<Shift__c> shifts = [
            SELECT Timezone__c, Start_Hour__c, End_Hour__c
            FROM Shift__c
            WHERE Is_Active__c = true
        ];
        for (Shift__c s : shifts) {
            Integer localHour = Integer.valueOf(DateTime.now().format('H', s.Timezone__c));
            if (isWithinShift(localHour, Integer.valueOf(s.Start_Hour__c), Integer.valueOf(s.End_Hour__c))) {
                activeCount++;
            }
        }
        summary.activeShiftCount = activeCount;
        summary.totalShiftCount = shifts.size();

        return summary;
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
    }

    public class DashboardSummary {
        @AuraEnabled public Integer totalWaiting;
        @AuraEnabled public Integer totalAssigned;
        @AuraEnabled public Integer totalCompleted;
        @AuraEnabled public Integer activeShiftCount;
        @AuraEnabled public Integer totalShiftCount;
    }
}
