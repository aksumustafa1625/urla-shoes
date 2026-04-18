// Önce temizlik
delete [SELECT Id FROM Lead_Queue__c];
delete [SELECT Id FROM SLA_Breach_Log__c];
delete [SELECT Id FROM Lead WHERE Company LIKE 'Urla Shoes Lead%'];
List<Shift__c> allShifts = [SELECT Id, Current_Lead_Count__c FROM Shift__c];
for (Shift__c s : allShifts) s.Current_Lead_Count__c = 0;
update allShifts;

// Shift bilgileri
Map<String, Integer> leadCounts = new Map<String, Integer>();
leadCounts.put('Tokyo Night Shift', 13);
leadCounts.put('Lagos Morning Shift', 18);
leadCounts.put('Auckland Evening Shift', 7);
leadCounts.put('NewYork Afternoon Shift', 22);

Integer waitingCount = 10;

List<Shift__c> shifts = [
    SELECT Id, Name, Assigned_User__c, Assigned_User__r.Name
    FROM Shift__c
    WHERE Is_Active__c = true
];

Map<String, Shift__c> shiftMap = new Map<String, Shift__c>();
for (Shift__c s : shifts) {
    shiftMap.put(s.Name, s);
}

List<String> firstNames = new List<String>{
    'Ali','Fatma','Mehmet','Ayse','Emre','Zeynep','Can','Elif','Burak','Selin',
    'Omar','Amina','Yusuf','Hana','Tariq','Layla','Kenji','Yuki','Riku','Sakura',
    'James','Sarah','Mike','Emma','Chris','Olivia','David','Sofia','Alex','Maria',
    'Tane','Aroha','Nikau','Mia','Sami','Lina','Amir','Nora','Efe','Defne',
    'John','Jane','Tom','Lucy','Jack','Rose','Leo','Zoe','Max','Lily',
    'Kai','Nina','Ren','Isla','Hugo','Clara','Finn','Ava','Noah','Ella',
    'Adam','Eve','Ryan','Amy','Sean','Jade','Luke','Ruby','Cole','Mila'
};

List<String> lastNames = new List<String>{
    'Yilmaz','Kaya','Demir','Celik','Sahin','Arslan','Dogan','Kilic','Aslan','Ozturk',
    'Adeyemi','Okonkwo','Balogun','Ibrahim','Hassan','Mohammed','Tanaka','Suzuki','Sato','Watanabe',
    'Smith','Johnson','Williams','Brown','Jones','Davis','Wilson','Taylor','Anderson','Thomas',
    'TeAwa','Henare','Wiremu','Kapua','Mansour','Rahman','Osman','Farah','Aydin','Korkmaz',
    'Miller','Garcia','Martinez','Lee','Harris','Clark','Lewis','Hall','Young','King',
    'Baker','Green','Adams','Nelson','Hill','Scott','Turner','White','Moore','Walker',
    'Reed','Bell','Ward','Ross','Wood','Long','Shaw','Hunt','Cole','Stone'
};

// Lead'leri oluştur - trigger otomatik Lead_Queue__c yaratacak
List<Lead> allLeads = new List<Lead>();
Integer nameIndex = 0;

for (String shiftName : leadCounts.keySet()) {
    Shift__c shift = shiftMap.get(shiftName);
    if (shift == null) continue;

    Integer count = leadCounts.get(shiftName);
    for (Integer i = 0; i < count; i++) {
        allLeads.add(new Lead(
            FirstName = firstNames[Math.mod(nameIndex, 70)],
            LastName = lastNames[Math.mod(nameIndex, 70)],
            Company = 'Urla Shoes Lead ' + (nameIndex + 1),
            Status = 'Open - Not Contacted',
            OwnerId = shift.Assigned_User__c,
            LeadSource = Math.mod(nameIndex, 3) == 0 ? 'Web' : (Math.mod(nameIndex, 3) == 1 ? 'Phone' : 'Email'),
            Rating = Math.mod(nameIndex, 4) == 0 ? 'Hot' : (Math.mod(nameIndex, 4) == 1 ? 'Warm' : 'Cold')
        ));
        nameIndex++;
    }
}

// Waiting lead'ler (owner olmadan)
for (Integer i = 0; i < waitingCount; i++) {
    allLeads.add(new Lead(
        FirstName = firstNames[Math.mod(nameIndex, 70)],
        LastName = lastNames[Math.mod(nameIndex, 70)],
        Company = 'Urla Shoes Lead ' + (nameIndex + 1),
        Status = 'Open - Not Contacted',
        LeadSource = 'Web',
        Rating = 'Hot'
    ));
    nameIndex++;
}

insert allLeads;

// Trigger Lead_Queue__c kayıtlarını oluşturdu. Şimdi bunları Completed olarak güncelle.
Set<Id> leadIds = new Set<Id>();
for (Lead l : allLeads) leadIds.add(l.Id);

List<Lead_Queue__c> queues = [
    SELECT Id, Lead__c, Status__c, Assigned_To__c
    FROM Lead_Queue__c
    WHERE Lead__c IN :leadIds
];

// Waiting lead ID'leri (son 10)
Set<Id> waitingLeadIds = new Set<Id>();
for (Integer i = 60; i < 70; i++) {
    waitingLeadIds.add(allLeads[i].Id);
}

List<Lead_Queue__c> toUpdate = new List<Lead_Queue__c>();
for (Lead_Queue__c q : queues) {
    if (!waitingLeadIds.contains(q.Lead__c)) {
        q.Status__c = 'Completed';
        toUpdate.add(q);
    }
}

if (!toUpdate.isEmpty()) update toUpdate;

// Shift count'ları sıfırla (completed oldukları için aktif yük yok)
List<Shift__c> resetShifts = [SELECT Id, Current_Lead_Count__c FROM Shift__c];
for (Shift__c s : resetShifts) s.Current_Lead_Count__c = 0;
update resetShifts;

// Sonuç kontrol
Integer totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed' AND Lead__c IN :leadIds];
Integer totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting' AND Lead__c IN :leadIds];
Integer totalAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned' AND Lead__c IN :leadIds];

System.debug('=== SONUC ===');
System.debug('Toplam Lead: ' + allLeads.size());
System.debug('Completed: ' + totalCompleted);
System.debug('Waiting: ' + totalWaiting);
System.debug('Assigned: ' + totalAssigned);
