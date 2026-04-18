// Gerçek assigned lead sayılarını hesapla
Map<Id, Integer> actualCounts = new Map<Id, Integer>();
for (AggregateResult ar : [
    SELECT Assigned_To__c userId, COUNT(Id) cnt
    FROM Lead_Queue__c
    WHERE Status__c = 'Assigned'
    GROUP BY Assigned_To__c
]) {
    actualCounts.put((Id)ar.get('userId'), (Integer)ar.get('cnt'));
}

// Shift'lere yaz
List<Shift__c> shifts = [SELECT Id, Name, Assigned_User__c, Current_Lead_Count__c FROM Shift__c];
for (Shift__c s : shifts) {
    Integer realCount = actualCounts.containsKey(s.Assigned_User__c) ? actualCounts.get(s.Assigned_User__c) : 0;
    s.Current_Lead_Count__c = realCount;
}
update shifts;

// Kapasiteyi aşan Assigned lead'leri Waiting'e çek (fazladan atananlar)
List<Shift__c> allShifts = [
    SELECT Id, Assigned_User__c, Max_Capacity__c
    FROM Shift__c
    WHERE Is_Active__c = true
];

Map<Id, Integer> capacityByUser = new Map<Id, Integer>();
for (Shift__c s : allShifts) {
    capacityByUser.put(s.Assigned_User__c, Integer.valueOf(s.Max_Capacity__c));
}

List<Lead_Queue__c> toWaiting = new List<Lead_Queue__c>();
List<Lead> leadOwnerReset = new List<Lead>();

for (Id userId : actualCounts.keySet()) {
    Integer actual = actualCounts.get(userId);
    Integer maxCap = capacityByUser.containsKey(userId) ? capacityByUser.get(userId) : 1;

    if (actual > maxCap) {
        Integer excess = actual - maxCap;
        List<Lead_Queue__c> extras = [
            SELECT Id, Lead__c, Name
            FROM Lead_Queue__c
            WHERE Status__c = 'Assigned'
            AND Assigned_To__c = :userId
            ORDER BY Assigned_At__c DESC
            LIMIT :excess
        ];

        for (Lead_Queue__c e : extras) {
            e.Status__c = 'Waiting';
            e.Assigned_To__c = null;
            e.Assigned_At__c = null;
            e.SLA_Deadline__c = null;
            e.Queue_Entry_Time__c = DateTime.now();
            String leadPart = e.Name.substringAfterLast('| ');
            e.Name = 'LQ | Waiting | ' + leadPart;
            toWaiting.add(e);

            if (e.Lead__c != null) {
                leadOwnerReset.add(new Lead(Id = e.Lead__c));
            }
        }
    }
}

if (!toWaiting.isEmpty()) update toWaiting;

// Count'ları tekrar senkronize et
Map<Id, Integer> newCounts = new Map<Id, Integer>();
for (AggregateResult ar : [
    SELECT Assigned_To__c userId, COUNT(Id) cnt
    FROM Lead_Queue__c
    WHERE Status__c = 'Assigned'
    GROUP BY Assigned_To__c
]) {
    newCounts.put((Id)ar.get('userId'), (Integer)ar.get('cnt'));
}

for (Shift__c s : shifts) {
    s.Current_Lead_Count__c = newCounts.containsKey(s.Assigned_User__c) ? newCounts.get(s.Assigned_User__c) : 0;
}
update shifts;

// Sonuç
Integer totalAssigned = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Assigned'];
Integer totalWaiting = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Waiting'];
Integer totalCompleted = [SELECT COUNT() FROM Lead_Queue__c WHERE Status__c = 'Completed'];

System.debug('=== SONUC ===');
System.debug('Assigned: ' + totalAssigned);
System.debug('Waiting: ' + totalWaiting);
System.debug('Completed: ' + totalCompleted);

for (Shift__c s : [SELECT Name, Assigned_User__r.Name, Current_Lead_Count__c, Max_Capacity__c FROM Shift__c WHERE Is_Active__c = true]) {
    System.debug(s.Name + ' | ' + s.Assigned_User__r.Name + ' | ' + s.Current_Lead_Count__c + '/' + s.Max_Capacity__c);
}
