List<AggregateResult> byUser = [
    SELECT Assigned_To__c userId, Assigned_To__r.Name assignee, Status__c status, COUNT(Id) cnt
    FROM Lead_Queue__c
    WHERE Status__c = 'Completed'
    GROUP BY Assigned_To__c, Assigned_To__r.Name, Status__c
];

System.debug('=== COMPLETED BY USER ===');
for (AggregateResult ar : byUser) {
    System.debug(ar.get('assignee') + ' (' + ar.get('userId') + ') | ' + ar.get('cnt'));
}

// Shift user ID'leri
List<Shift__c> shifts = [SELECT Name, Assigned_User__c, Assigned_User__r.Name FROM Shift__c WHERE Is_Active__c = true];
System.debug('=== SHIFT USERS ===');
for (Shift__c s : shifts) {
    System.debug(s.Name + ' | User: ' + s.Assigned_User__r.Name + ' (' + s.Assigned_User__c + ')');
}

// Null assigned completed var mi?
Integer nullCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed' AND Assigned_To__c = null];
System.debug('Assigned_To null Completed: ' + nullCompleted);
