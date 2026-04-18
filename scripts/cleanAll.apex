delete [SELECT Id FROM Lead_Queue__c];
delete [SELECT Id FROM SLA_Breach_Log__c];
delete [SELECT Id FROM Lead WHERE Company LIKE 'Urla Shoes Lead%'];
List<Shift__c> shifts = [SELECT Id, Current_Lead_Count__c FROM Shift__c];
for (Shift__c s : shifts) s.Current_Lead_Count__c = 0;
update shifts;
System.debug('Temizlik tamamlandi');
