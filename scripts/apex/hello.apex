/**
List<Shift__c> shifts = [SELECT Name, Timezone__c, Start_Hour__c, End_Hour__c FROM Shift__c WHERE Is_Active__c = true];

Map<String, Integer> utcOffset = new Map<String, Integer>();
utcOffset.put('Africa/Lagos', 1);
utcOffset.put('America/New_York', -5);
utcOffset.put('Pacific/Auckland', 12);
utcOffset.put('Asia/Tokyo', 9);

for (Shift__c s : shifts) {
    Integer offset = utcOffset.get(s.Timezone__c);
    Integer localStart = Math.mod((Integer)s.Start_Hour__c + offset, 24);
    Integer localEnd = Math.mod((Integer)s.End_Hour__c + offset, 24);
    System.debug(s.Name + ' | UTC: ' + (Integer)s.Start_Hour__c + ':00 - ' + (Integer)s.End_Hour__c + ':00 | Yerel: ' + localStart + ':00 - ' + localEnd + ':00 | Lagos: ' + Math.mod((Integer)s.Start_Hour__c + 1, 24) + ':00 - ' + Math.mod((Integer)s.End_Hour__c + 1, 24) + ':00');
}



 */
delete[SELECT id FROM Lead WHERE CreatedDate = LAST_N_DAYS:3];
delete [SELECT Id FROM Lead_Queue__c WHERE CreatedDate = LAST_N_DAYS:3];
delete [SELECT Id FROM SLA_Breach_Log__c WHERE CreatedDate = LAST_N_DAYS:15];

insert new List<Lead>{
    new Lead(FirstName='Lead', LastName='One', Company='One GmbH', Rating='Hot', LeadSource='Web'),
    new Lead(FirstName='Lead', LastName='Two', Company='Two GmbH', Rating='Hot', LeadSource='Web')
};
new Lead(FirstName='Lead', LastName='Three', Company='Three GmbH', Rating='Warm', LeadSource='Phone'),
new Lead(FirstName='Lead', LastName='Four', Company='Four GmbH', Rating='Hot', LeadSource='Web'),
new Lead(FirstName='Lead', LastName='Five', Company='Three GmbH', Rating='Warm', LeadSource='Phone'),
new Lead(FirstName='Lead', LastName='Six', Company='Four GmbH', Rating='Hot', LeadSource='Web')