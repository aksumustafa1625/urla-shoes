// Completed ama Assigned_To null olanları bul
List<Lead_Queue__c> nullAssigned = [
    SELECT Id, Lead__c, Lead__r.OwnerId, Lead__r.Owner.Name
    FROM Lead_Queue__c
    WHERE Status__c = 'Completed'
    AND Assigned_To__c = null
];

System.debug('Düzeltilecek kayıt: ' + nullAssigned.size());

List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
for (Lead_Queue__c q : nullAssigned) {
    q.Assigned_To__c = q.Lead__r.OwnerId;

    String leadName = q.Lead__c != null ? '' : 'Unknown';
    String ownerName = q.Lead__r.Owner.Name != null ? q.Lead__r.Owner.Name : 'Unknown';
    q.Name = 'LQ | ' + ownerName + ' | Completed';

    toUpdate.add(q);
}

if (!toUpdate.isEmpty()) update toUpdate;

// Doğrula
List<AggregateResult> byUser = [
    SELECT Assigned_To__r.Name assignee, COUNT(Id) cnt
    FROM Lead_Queue__c
    WHERE Status__c = 'Completed'
    GROUP BY Assigned_To__r.Name
];

System.debug('=== DUZELTME SONRASI ===');
for (AggregateResult ar : byUser) {
    System.debug(ar.get('assignee') + ' | Completed: ' + ar.get('cnt'));
}
