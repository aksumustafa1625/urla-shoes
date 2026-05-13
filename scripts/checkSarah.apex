List<Lead_Queue__c> sarahs = [
    SELECT Id, Name, Status__c, Assigned_To__r.Name, Lead__r.Name, Assigned_At__c, LastModifiedDate
    FROM Lead_Queue__c
    WHERE Assigned_To__r.Name = 'Sarah NewYork'
    ORDER BY LastModifiedDate DESC
];

System.debug('=== SARAH TUM KAYITLAR ===');
System.debug('Toplam: ' + sarahs.size());
for (Lead_Queue__c q : sarahs) {
    System.debug(q.Name + ' | Status: ' + q.Status__c + ' | Lead: ' + q.Lead__r.Name + ' | Modified: ' + q.LastModifiedDate);
}
