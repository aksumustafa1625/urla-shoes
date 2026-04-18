// Mevcut assigned lead'leri al
List<Lead_Queue__c> assigned = [
    SELECT Id, Name, Status__c, Assigned_To__c, Assigned_To__r.Name
    FROM Lead_Queue__c
    WHERE Status__c = 'Assigned'
];

System.debug('=== ONCE ===');
System.debug('Assigned: ' + assigned.size());
for (Lead_Queue__c q : assigned) {
    System.debug('  - ' + q.Name + ' (To: ' + q.Assigned_To__r.Name + ')');
}
Integer beforeWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
Integer beforeCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];
System.debug('Waiting: ' + beforeWaiting);
System.debug('Completed: ' + beforeCompleted);

// İkisini de Completed yap
for (Lead_Queue__c q : assigned) {
    q.Status__c = 'Completed';
}
update assigned;

// Trigger otomatik çalışacak: rename + backfill

Integer afterAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
Integer afterWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
Integer afterCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];

System.debug('=== SONRA ===');
System.debug('Assigned: ' + afterAssigned);
System.debug('Waiting: ' + afterWaiting);
System.debug('Completed: ' + afterCompleted);

List<Lead_Queue__c> newAssigned = [
    SELECT Name, Assigned_To__r.Name
    FROM Lead_Queue__c
    WHERE Status__c = 'Assigned'
];
System.debug('=== YENI ASSIGNED ===');
for (Lead_Queue__c q : newAssigned) {
    System.debug('  - ' + q.Name + ' (To: ' + q.Assigned_To__r.Name + ')');
}

// Completed olanların ismi doğru mu?
List<Lead_Queue__c> lastCompleted = [
    SELECT Name, Assigned_To__r.Name
    FROM Lead_Queue__c
    WHERE Status__c = 'Completed'
    ORDER BY LastModifiedDate DESC
    LIMIT 2
];
System.debug('=== SON COMPLETED ===');
for (Lead_Queue__c q : lastCompleted) {
    System.debug('  - ' + q.Name);
}
