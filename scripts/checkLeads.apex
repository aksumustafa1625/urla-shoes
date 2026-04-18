Integer totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
Integer totalAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
Integer totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];
Integer totalAll = [SELECT COUNT() FROM Lead_Queue__c];

System.debug('=== LEAD QUEUE DURUM ===');
System.debug('Toplam: ' + totalAll);
System.debug('Waiting: ' + totalWaiting);
System.debug('Assigned: ' + totalAssigned);
System.debug('Completed: ' + totalCompleted);

List<AggregateResult> byUser = [
    SELECT Assigned_To__r.Name assignee, Status__c status, COUNT(Id) cnt
    FROM Lead_Queue__c
    GROUP BY Assigned_To__r.Name, Status__c
    ORDER BY Assigned_To__r.Name
];

System.debug('=== KISI BAZLI ===');
for (AggregateResult ar : byUser) {
    System.debug(ar.get('assignee') + ' | ' + ar.get('status') + ' | ' + ar.get('cnt'));
}
