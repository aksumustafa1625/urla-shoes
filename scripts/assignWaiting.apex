List<Lead_Queue__c> waiting = [
    SELECT Id, Lead__c, Status__c, Priority__c
    FROM Lead_Queue__c
    WHERE Status__c = 'Waiting'
    ORDER BY Queue_Entry_Time__c ASC
];

LeadQueueProcessor.processWaitingEntries(waiting);

Integer totalAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
Integer totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
Integer totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];

System.debug('=== SONUC ===');
System.debug('Assigned: ' + totalAssigned);
System.debug('Waiting: ' + totalWaiting);
System.debug('Completed: ' + totalCompleted);

for (Shift__c s : [SELECT Name, Assigned_User__r.Name, Current_Lead_Count__c, Max_Capacity__c FROM Shift__c WHERE Is_Active__c = true]) {
    System.debug(s.Name + ' | ' + s.Assigned_User__r.Name + ' | ' + s.Current_Lead_Count__c + '/' + s.Max_Capacity__c);
}
