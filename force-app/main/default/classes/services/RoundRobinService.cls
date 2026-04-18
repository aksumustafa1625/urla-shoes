/**
 * RoundRobinService
 *
 * Purpose:
 * - Centralized round-robin selection utilities for shift-based Lead assignment.
 * - Chooses the next rep/shift with the lowest Current_Lead_Count__c to balance workload.
 *
 * Responsibilities:
 * - getNextAssignee(): Return the User Id from the shift with the fewest active leads.
 * - getNextShift(): Return the Shift__c record with the fewest active leads.
 * - incrementLeadCount(): Persistently increment the selected shift's load counter.
 *
 * Notes:
 * - Methods are bulk-safe when invoked per selection (no DML in loops recommended; use upstream batching).
 * - incrementLeadCount performs a single-record update; callers should avoid calling it inside deep loops
 *   if they can batch work in memory first and persist afterwards.
 *
 * Author: Mustafa Bey
 * Since: 2026
 */
public with sharing class RoundRobinService {

    /**
     * Returns the User Id from the shift that currently has the lowest lead count.
     * Fast-exits when the provided activeShifts list is null/empty.
     */
    public static Id getNextAssignee(List<Shift__c> activeShifts) {

        if (activeShifts == null || activeShifts.isEmpty()) {
            return null;
        }

        Shift__c selectedShift = null;
        Decimal lowestCount = null;

        for (Shift__c shift : activeShifts) {

            Decimal count = shift.Current_Lead_Count__c != null
                ? shift.Current_Lead_Count__c
                : 0;

            if (lowestCount == null || count < lowestCount) {
                lowestCount = count;
                selectedShift = shift;
            }
        }

        return selectedShift != null
            ? selectedShift.Assigned_User__c
            : null;
    }

    /**
     * Returns the Shift__c with the lowest Current_Lead_Count__c.
     * Useful when the caller needs both the assignee and shift metadata.
     */
    public static Shift__c getNextShift(List<Shift__c> activeShifts) {

        if (activeShifts == null || activeShifts.isEmpty()) {
            return null;
        }

        Shift__c selectedShift = null;
        Decimal lowestCount = null;

        for (Shift__c shift : activeShifts) {

            Decimal count = shift.Current_Lead_Count__c != null
                ? shift.Current_Lead_Count__c
                : 0;

            if (lowestCount == null || count < lowestCount) {
                lowestCount = count;
                selectedShift = shift;
            }
        }

        return selectedShift;
    }

    /**
     * Increments the Current_Lead_Count__c for the given Shift__c.
     * Performs a single-record DML update; callers should prefer batching at a higher layer if needed.
     */
    public static void incrementLeadCount(Id shiftId) {

        if (shiftId == null) {
            return;
        }

        List<Shift__c> shifts = [
            SELECT Id, Current_Lead_Count__c
            FROM Shift__c
            WHERE Id = :shiftId
            LIMIT 1
        ];

        if (shifts.isEmpty()) {
            return;
        }

        Shift__c shift = shifts[0];
        shift.Current_Lead_Count__c =
            (shift.Current_Lead_Count__c != null
                ? shift.Current_Lead_Count__c
                : 0) + 1;

        update shift;
    }
}
