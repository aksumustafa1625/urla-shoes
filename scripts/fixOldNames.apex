// Completed ama ismi "Completed" ile bitmeyen kayıtları bul
List<Lead_Queue__c> badNames = [
    SELECT Id, Name, Assigned_To__r.Name, Status__c
    FROM Lead_Queue__c
    WHERE Status__c = 'Completed'
    AND (NOT Name LIKE '%Completed')
];

System.debug('Düzeltilecek: ' + badNames.size());

for (Lead_Queue__c q : badNames) {
    String assignee = q.Assigned_To__r != null ? q.Assigned_To__r.Name : 'Unknown';
    q.Name = 'LQ | ' + assignee + ' | Completed';
}

if (!badNames.isEmpty()) update badNames;

System.debug('Duzeltme tamamlandi');
