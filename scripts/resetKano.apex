Reseller__c r = [SELECT Id, Name FROM Reseller__c WHERE Name = 'Kano Shop' ORDER BY CreatedDate DESC LIMIT 1];
List<Document_Request__c> openReqs = [
    SELECT Id FROM Document_Request__c WHERE Reseller__c = :r.Id AND Status__c = 'Requested'
];
System.debug('DIAG openBefore=' + openReqs.size());
if (!openReqs.isEmpty()) { delete openReqs; }
Integer left = [SELECT COUNT() FROM Document_Request__c WHERE Reseller__c = :r.Id AND Status__c = 'Requested'];
System.debug('DIAG openAfter=' + left + ' -> button click will now create fresh requests + email the primary contact');
