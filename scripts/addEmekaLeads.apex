// Mevcut durum
Integer sarahCount = [
    SELECT COUNT()
    FROM Lead_Queue__c
    WHERE Assigned_To__r.Name = 'Sarah NewYork'
    AND Status__c = 'Completed'
];
Integer emekaCount = [
    SELECT COUNT()
    FROM Lead_Queue__c
    WHERE Assigned_To__r.Name = 'Emeka Lagos'
    AND Status__c = 'Completed'
];
System.debug('Önce - Sarah: ' + sarahCount + ', Emeka: ' + emekaCount);

// Emeka shift bilgisi
Shift__c emekaShift = [
    SELECT Id, Assigned_User__c, Assigned_User__r.Name
    FROM Shift__c
    WHERE Name = 'Lagos Morning Shift'
    LIMIT 1
];

// 4 yeni completed lead ekle
List<Lead> newLeads = new List<Lead>();
for (Integer i = 0; i < 4; i++) {
    newLeads.add(new Lead(
        FirstName = 'Bonus',
        LastName = 'Lead ' + (i + 1),
        Company = 'Urla Shoes Bonus ' + (i + 1),
        Status = 'Open - Not Contacted',
        OwnerId = emekaShift.Assigned_User__c,
        LeadSource = 'Web',
        Rating = 'Hot'
    ));
}
insert newLeads;

// Trigger Lead_Queue__c oluşturdu — onları Completed + Emeka olarak güncelle
Set<Id> newLeadIds = new Set<Id>();
for (Lead l : newLeads) newLeadIds.add(l.Id);

List<Lead_Queue__c> queues = [
    SELECT Id, Status__c
    FROM Lead_Queue__c
    WHERE Lead__c IN :newLeadIds
];

for (Lead_Queue__c q : queues) {
    q.Status__c = 'Completed';
    q.Assigned_To__c = emekaShift.Assigned_User__c;
}
update queues;

// Shift count'u sıfırla (completed oldukları için yük yok)
emekaShift.Current_Lead_Count__c = [
    SELECT COUNT()
    FROM Lead_Queue__c
    WHERE Assigned_To__c = :emekaShift.Assigned_User__c
    AND Status__c = 'Assigned'
];
update emekaShift;

// Sonrası
Integer sarahCountAfter = [
    SELECT COUNT() FROM Lead_Queue__c
    WHERE Assigned_To__r.Name = 'Sarah NewYork' AND Status__c = 'Completed'
];
Integer emekaCountAfter = [
    SELECT COUNT() FROM Lead_Queue__c
    WHERE Assigned_To__r.Name = 'Emeka Lagos' AND Status__c = 'Completed'
];
System.debug('Sonra - Sarah: ' + sarahCountAfter + ', Emeka: ' + emekaCountAfter);
