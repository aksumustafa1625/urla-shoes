/**
 * @description
 * Selector layer for Shift__c records.
 * Finds active shifts based on current local time per timezone.
 *
 * @author Mustafa Bey
 * @created 2026
 */
public with sharing class ShiftSelector {

    /**
     * Returns all active shifts where current local time
     * falls within the shift hours
     */
    public static List<Shift__c> getActiveShifts() {

    List<Shift__c> allShifts = [
        SELECT Id,
               Assigned_User__c,
               Timezone__c,
               Start_Hour__c,
               End_Hour__c,
               Is_Active__c,
               Current_Lead_Count__c,
               Max_Capacity__c
        FROM Shift__c
        WHERE Is_Active__c = true
    ];

    List<Shift__c> activeShifts = new List<Shift__c>();

    for (Shift__c shift : allShifts) {

        Boolean withinShift = TimezoneService.isWithinShift(
            shift.Timezone__c,
            Integer.valueOf(shift.Start_Hour__c),
            Integer.valueOf(shift.End_Hour__c)
        );

        Decimal currentCount = shift.Current_Lead_Count__c != null
            ? shift.Current_Lead_Count__c : 0;
        Decimal maxCapacity = shift.Max_Capacity__c != null
            ? shift.Max_Capacity__c : 1;

        Boolean hasCapacity = currentCount < maxCapacity;

        if (withinShift && hasCapacity) {
            activeShifts.add(shift);
        }
    }

    return activeShifts;
}

    /**
     * Returns already logged queue IDs for given leads
     * to prevent duplicate queue entries
     */
    public static Set<Id> getAlreadyQueuedLeadIds(Set<Id> leadIds) {

        Set<Id> result = new Set<Id>();

        if (leadIds == null || leadIds.isEmpty()) {
            return result;
        }

        for (Lead_Queue__c q : [
            SELECT Lead__c
            FROM Lead_Queue__c
            WHERE Lead__c IN :leadIds
            AND Status__c NOT IN ('Completed')
        ]) {
            result.add(q.Lead__c);
        }

        return result;
    }
}
