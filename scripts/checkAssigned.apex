List<Lead_Queue__c> assigned = [
    SELECT Id, Name, Status__c, Assigned_To__r.Name, Assigned_At__c
    FROM Lead_Queue__c
    WHERE Status__c = 'Assigned'
    ORDER BY Assigned_At__c DESC
];

System.debug('=== ASSIGNED LEADS ===');
for (Lead_Queue__c q : assigned) {
    System.debug(q.Name + ' | To: ' + q.Assigned_To__r.Name + ' | At: ' + q.Assigned_At__c);
}

List<Shift__c> shifts = [
    SELECT Name, Assigned_User__r.Name, Current_Lead_Count__c, Max_Capacity__c, Is_Active__c
    FROM Shift__c
    WHERE Is_Active__c = true
];

System.debug('=== SHIFT CAPACITY ===');
for (Shift__c s : shifts) {
    System.debug(s.Name + ' | ' + s.Assigned_User__r.Name + ' | Count: ' + s.Current_Lead_Count__c + '/' + s.Max_Capacity__c);
}
